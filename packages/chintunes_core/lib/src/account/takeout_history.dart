import 'dart:convert';

import '../models/track.dart';
import 'youtube_library_mapper.dart';

/// One play from local history or an imported Google Takeout file.
class HistoryEntry {
  const HistoryEntry({required this.track, required this.playedAt, required this.isMusic, required this.origin});

  final Track track;
  final DateTime playedAt;
  final bool isMusic;

  /// `local` or `takeout`.
  final String origin;
}

/// Parses Google Takeout `YouTube and YouTube Music/history/watch-history.json`.
///
/// YouTube Data API v3 no longer exposes watch history (the `HL` /
/// `watchHistory` playlist returns empty), so users export it from
/// takeout.google.com and import the JSON. Entry shape:
/// ```json
/// {"header":"YouTube Music","title":"Watched Kesariya",
///  "titleUrl":"https://www.youtube.com/watch?v=BddP6PYo2gs",
///  "subtitles":[{"name":"Arijit Singh - Topic","url":"…"}],
///  "time":"2024-05-01T10:00:00.000Z","products":["YouTube"]}
/// ```
/// Ads (`details: [{"name":"From Google Ads"}]`), removed videos (no
/// `titleUrl`) and survey entries are skipped.
abstract final class TakeoutHistoryParser {
  static final RegExp _watchedPrefix = RegExp(r'^(?:Watched|Listened to)\s+', caseSensitive: false);

  static List<HistoryEntry> parse(String jsonText, {bool musicOnly = false}) {
    final decoded = jsonDecode(jsonText);
    if (decoded is! List) {
      throw const FormatException('Expected a watch-history.json array (Google Takeout, JSON format).');
    }
    final out = <HistoryEntry>[];
    for (final raw in decoded.whereType<Map<dynamic, dynamic>>()) {
      final details = raw['details'];
      if (details is List &&
          details.whereType<Map<dynamic, dynamic>>().any((d) => '${d['name']}'.contains('Google Ads'))) {
        continue;
      }
      final url = raw['titleUrl']?.toString();
      if (url == null) continue;
      final uri = Uri.tryParse(url.replaceAll(r'=', '='));
      final videoId = uri?.queryParameters['v'];
      if (videoId == null || videoId.isEmpty) continue;
      final playedAt = DateTime.tryParse(raw['time']?.toString() ?? '');
      if (playedAt == null) continue;

      final title = (raw['title']?.toString() ?? '').replaceFirst(_watchedPrefix, '');
      final subtitles = raw['subtitles'];
      final channel = (subtitles is List && subtitles.isNotEmpty && subtitles.first is Map)
          ? ((subtitles.first as Map<dynamic, dynamic>)['name']?.toString() ?? '')
          : '';
      final header = raw['header']?.toString() ?? '';
      final isMusic = header == 'YouTube Music' || YouTubeLibraryMapper.isMusic(channelTitle: channel, title: title);
      if (musicOnly && !isMusic) continue;

      out.add(HistoryEntry(
        track: YouTubeLibraryMapper.trackFrom(videoId: videoId, rawTitle: title, channelTitle: channel),
        playedAt: playedAt.toUtc(),
        isMusic: isMusic,
        origin: 'takeout',
      ));
    }
    out.sort((a, b) => b.playedAt.compareTo(a.playedAt));
    return out;
  }
}
