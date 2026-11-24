import '../data/data_mode.dart';
import '../models/collection.dart';
import '../models/resolved_stream.dart';
import '../models/track.dart';

/// Abstraction over YouTube search + audio extraction.
///
/// The CLI used `yt-dlp` (Python, unavailable on Android). The app uses
/// `youtube_explode_dart` via [YoutubeExplodeSource]; tests use a fake.
abstract interface class YouTubeSource {
  Future<List<Track>> search(String query, {int limit = 10});

  /// Metadata for a single video id (share links).
  Future<Track?> video(String videoId);

  /// Audio-only stream picked for [mode] (Opus itag 249/250/251 preferred,
  /// see `StreamSelector.pickYouTube`). URLs are signed and expire (~6h):
  /// resolve lazily at play time and never persist them.
  Future<ResolvedStream> resolveAudio(String videoId, {DataMode mode = DataMode.high});

  Future<MediaCollection?> playlist(String playlistId, {int limit = 200});

  void close();
}
