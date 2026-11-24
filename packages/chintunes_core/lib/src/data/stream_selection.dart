import '../models/track.dart';
import 'data_mode.dart';

/// One audio-only rendition offered by YouTube (decoupled from
/// youtube_explode types so selection is unit-testable).
class AudioStreamCandidate {
  const AudioStreamCandidate({
    required this.itag,
    required this.bitrateKbps,
    required this.codec,
    required this.container,
    required this.url,
    this.sizeBytes,
  });

  final int itag;
  final int bitrateKbps;

  /// e.g. `opus`, `mp4a.40.2`.
  final String codec;

  /// e.g. `webm`, `mp4`.
  final String container;
  final Uri url;
  final int? sizeBytes;

  bool get isOpus => codec.toLowerCase().contains('opus');

  @override
  String toString() => 'itag $itag ($codec ${bitrateKbps}k)';
}

abstract final class StreamSelector {
  /// Picks the YouTube audio-only stream for [mode]:
  /// 1. first itag in [DataMode.youtubeItagPreference] that is offered;
  /// 2. otherwise (unknown itags) the Opus stream closest to the target
  ///    bitrate, then any stream closest to the target. Ties go lower for
  ///    saver modes and higher for High.
  static AudioStreamCandidate? pickYouTube(List<AudioStreamCandidate> candidates, DataMode mode) {
    if (candidates.isEmpty) return null;
    for (final itag in mode.youtubeItagPreference) {
      for (final c in candidates) {
        if (c.itag == itag) return c;
      }
    }
    final opus = candidates.where((c) => c.isOpus).toList();
    final pool = opus.isNotEmpty ? opus : List<AudioStreamCandidate>.of(candidates);
    final target = mode.youtubeTargetKbps;
    pool.sort((a, b) {
      final da = (a.bitrateKbps - target).abs();
      final db = (b.bitrateKbps - target).abs();
      if (da != db) return da.compareTo(db);
      return mode == DataMode.high
          ? b.bitrateKbps.compareTo(a.bitrateKbps)
          : a.bitrateKbps.compareTo(b.bitrateKbps);
    });
    return pool.first;
  }

  /// JioSaavn AAC rendition: 96 / 160 / 320, with 320 → 160 fallback when
  /// the API does not flag the track as 320-capable.
  static int jioSaavnKbps(DataMode mode, {required bool has320}) {
    if (mode == DataMode.high && !has320) return DataMode.balanced.jioSaavnKbps;
    return mode.jioSaavnKbps;
  }

  /// What High mode would stream for [track]; the baseline for "data saved".
  static int highBaselineKbps(Track track) => switch (track.source) {
        TrackSource.jiosaavn => track.has320 ? 320 : 160,
        TrackSource.youtube ||
        TrackSource.spotify ||
        TrackSource.local ||
        TrackSource.deezer ||
        TrackSource.appleMusic =>
          160,
      };
}
