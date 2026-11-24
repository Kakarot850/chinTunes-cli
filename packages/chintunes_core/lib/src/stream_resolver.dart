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
      // Metadata-only tracks (imported Spotify / Deezer / Apple Music playlists).
      case TrackSource.spotify || TrackSource.deezer || TrackSource.appleMusic:
        if (sourcePreference == MusicSource.jiosaavn) {
          final match = await _matchJioSaavn(track);
          if (match != null) return _resolveJioSaavn(match, effectiveMode, matched: true);
        }
        return _viaYouTube(track, effectiveMode);
      case TrackSource.local:
        throw StreamResolveException('Local file missing: ${track.localPath}');
    }
  }

  /// `"<title> <artist> audio"` → best playable YouTube result (B-040).
  ///
  /// The CLI took the first result (`ytsearch1:`). On mobile that sometimes
  /// lands on a live stream, a Short or a long compilation that cannot be
  /// played, so up to [maxAttempts] ranked candidates are tried in order.
  Future<ResolvedStream> _viaYouTube(Track track, DataMode mode, {int maxAttempts = 3}) async {
    final results = await _youtube.search(youTubeQuery(track), limit: 8);
    final ranked = rankYouTubeMatches(results, track);
    if (ranked.isEmpty) {
      throw StreamResolveException('No YouTube match for "${track.title}"');
    }
    Object? lastError;
    for (final candidate in ranked.take(maxAttempts)) {
      try {
        return await _youtube.resolveAudio(candidate.id, mode: mode);
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError is StreamResolveException) throw lastError;
    throw StreamResolveException('No playable YouTube match for "${track.title}"');
  }

  /// Search query for matching a track on YouTube. Imported Spotify titles
  /// carry long "(feat. …) [From …]" suffixes and 5-artist credits that hurt
  /// search relevance, so brackets are dropped and only 2 artists are kept.
  static String youTubeQuery(Track track) {
    var title = track.title.replaceAll(RegExp(r'\s*[\(\[][^\)\]]*[\)\]]'), '').trim();
    if (title.isEmpty) title = track.title;
    final artists = track.artist == 'Unknown'
        ? const <String>[]
        : track.artist.split(RegExp(r'\s*,\s*|\s+&\s+')).where((a) => a.isNotEmpty).take(2).toList();
    return [title, ...artists, 'audio'].join(' ');
  }

  /// Orders YouTube search results for playing [wanted]:
  /// drops live streams (no duration) and Shorts (< 45 s); with a known
  /// target duration, prefers the closest length (search order breaks ties)
  /// and drops results more than 3 minutes off.
  static List<Track> rankYouTubeMatches(List<Track> results, Track wanted) {
    final playable = <({Track track, int order})>[];
    for (var i = 0; i < results.length; i++) {
      final d = results[i].durationSec;
      if (d == null || d < 45) continue;
      playable.add((track: results[i], order: i));
    }
    final target = wanted.durationSec;
    if (target == null || target <= 0) return [for (final p in playable) p.track];
    final close = playable.where((p) => (p.track.durationSec! - target).abs() <= 180).toList()
      ..sort((a, b) {
        // 10 s buckets count as equally good: keep YouTube's relevance order.
        final ba = (a.track.durationSec! - target).abs() ~/ 10;
        final bb = (b.track.durationSec! - target).abs() ~/ 10;
        return ba != bb ? ba.compareTo(bb) : a.order.compareTo(b.order);
      });
    return [for (final p in close) p.track];
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
