import 'dart:io';

import 'data/data_mode.dart';
import 'data/music_source.dart';
import 'data/stream_selection.dart';
import 'jiosaavn/jiosaavn_client.dart';
import 'jiosaavn/jiosaavn_crypto.dart';
import 'lyrics/lyrics_service.dart';
import 'models/resolved_stream.dart';
import 'models/track.dart';
import 'youtube/youtube_source.dart';

/// Returns an absolute path to an offline copy of [track], or null.
typedef OfflineLookup = String? Function(Track track);

/// Turns a [Track] into a playable [ResolvedStream] (port of the download
/// routing in `SyncCoordinator.process_track`):
///
/// 1. Offline copy on disk (`Track.localPath` or [offlineLookup]) → file uri,
///    zero network requests.
/// 2. JioSaavn track → direct AAC CDN url; bitrate from [DataMode]
///    (96 / 160 / 320 with 320→160 fallback). Only JioSaavn-origin tracks use
///    JioSaavn audio (CLI commit cc6c830).
/// 3. YouTube track → audio-only Opus stream picked for [DataMode].
/// 4. Spotify (metadata only) → `"<title> <artist> audio"` YouTube match.
class StreamResolver {
  StreamResolver({
    required JioSaavnClient jiosaavn,
    required YouTubeSource youtube,
    this.dataMode = DataMode.balanced,
    this.sourcePreference = MusicSource.auto,
    this.offlineLookup,
    bool Function(String path)? fileExists,
  })  : _jiosaavn = jiosaavn,
        _youtube = youtube,
        _fileExists = fileExists ?? ((p) => File(p).existsSync());

  final JioSaavnClient _jiosaavn;
  final YouTubeSource _youtube;
  final bool Function(String path) _fileExists;
  DataMode dataMode;

  /// Settings → Music source (cross-source matching, B-037).
  MusicSource sourcePreference;
  OfflineLookup? offlineLookup;

  /// Offline file for [track] if one exists on disk.
  String? offlinePathFor(Track track) {
    final candidates = [track.localPath, offlineLookup?.call(track)];
    for (final p in candidates) {
      if (p != null && p.isNotEmpty && _fileExists(p)) return p;
    }
    return null;
  }

  /// Resolves using [mode] (defaults to the global [dataMode]).
  /// Set [allowOffline] false to force a network stream (used by downloads).
  Future<ResolvedStream> resolve(Track track, {DataMode? mode, bool allowOffline = true}) async {
    final effectiveMode = mode ?? dataMode;
    if (allowOffline) {
      final local = offlinePathFor(track);
      if (local != null) {
        return ResolvedStream(
          uri: Uri.file(local),
          sourceLabel: 'Offline',
          isLocal: true,
          codec: _extOf(local),
        );
      }
    }

    switch (track.source) {
      case TrackSource.jiosaavn:
        if (sourcePreference == MusicSource.youtube) return _viaYouTube(track, effectiveMode);
        return _resolveJioSaavn(track, effectiveMode);
      case TrackSource.youtube:
        if (sourcePreference == MusicSource.jiosaavn) {
          final match = await _matchJioSaavn(track);
          if (match != null) return _resolveJioSaavn(match, effectiveMode, matched: true);
        }
        return _youtube.resolveAudio(track.id, mode: effectiveMode);
      case TrackSource.spotify:
        if (sourcePreference == MusicSource.jiosaavn) {
          final match = await _matchJioSaavn(track);
          if (match != null) return _resolveJioSaavn(match, effectiveMode, matched: true);
        }
        return _viaYouTube(track, effectiveMode);
      case TrackSource.local:
        throw StreamResolveException('Local file missing: ${track.localPath}');
    }
  }

  /// `"<title> <artist> audio"` → first YouTube result (CLI `ytsearch1:`).
  Future<ResolvedStream> _viaYouTube(Track track, DataMode mode) async {
    final matches = await _youtube.search('${track.title} ${track.artist} audio', limit: 1);
    if (matches.isEmpty) {
      throw StreamResolveException('No YouTube match for "${track.title}"');
    }
    return _youtube.resolveAudio(matches.first.id, mode: mode);
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  /// Best JioSaavn match for a YouTube/Spotify track, or null.
  /// Requires a playable result whose normalised title overlaps the query
  /// title, to avoid playing an unrelated song (B-037).
  Future<Track?> _matchJioSaavn(Track track) async {
    final title = LyricsService.sanitize(track.title);
    final artist = track.artist == 'Unknown' ? '' : track.artist;
    final List<Track> results;
    try {
      results = await _jiosaavn.searchSongs('$title $artist'.trim(), limit: 5);
    } catch (_) {
      return null;
    }
    final want = _norm(title);
    if (want.isEmpty) return null;
    for (final r in results) {
      if (r.mediaUrl == null) continue;
      final got = _norm(r.title);
      if (got.isEmpty) continue;
      if (got.contains(want) || want.contains(got)) return r;
    }
    return null;
  }

  int jioSaavnBitrateFor(Track track, [DataMode? mode]) =>
      StreamSelector.jioSaavnKbps(mode ?? dataMode, has320: track.has320);

  Future<ResolvedStream> _resolveJioSaavn(Track track, DataMode mode, {bool matched = false}) async {
    var base = track.mediaUrl;
    var effective = track;
    if (base == null || base.isEmpty) {
      final fresh = await _jiosaavn.songDetails([track.id]);
      if (fresh.isEmpty || fresh.first.mediaUrl == null) {
        throw StreamResolveException('No media url for JioSaavn song ${track.id}');
      }
      effective = fresh.first;
      base = effective.mediaUrl!;
    }
    final kbps = jioSaavnBitrateFor(effective, mode);
    return ResolvedStream(
      uri: Uri.parse(JioSaavnCrypto.withBitrate(base, kbps)),
      sourceLabel: matched ? 'JioSaavn (matched)' : 'JioSaavn',
      bitrateKbps: kbps,
      codec: 'AAC',
      container: 'mp4',
    );
  }

  static String? _extOf(String path) {
    final dot = path.lastIndexOf('.');
    return dot < 0 ? null : path.substring(dot + 1).toUpperCase();
  }
}
