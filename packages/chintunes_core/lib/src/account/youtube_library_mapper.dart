import '../lyrics/lyrics_service.dart';
import '../models/track.dart';
import '../util/artist_name.dart';
import '../util/html_text.dart';

/// A YouTube library item tagged as music / not music.
class TaggedTrack {
  const TaggedTrack(this.track, {required this.isMusic});

  final Track track;
  final bool isMusic;
}

/// Cleans YouTube video metadata into music-style tracks.
abstract final class YouTubeLibraryMapper {
  /// YouTube "Music" video category.
  static const String musicCategoryId = '10';

  static final RegExp _junk = RegExp(
    r'\s*[\(\[](?:official\s*)?(?:music\s*)?(?:video|audio|lyrics?|lyrical|visuali[sz]er|hd|4k|mv)[^\)\]]*[\)\]]',
    caseSensitive: false,
  );

  static bool isMusic({String? categoryId, String? channelTitle, String? title}) {
    if (categoryId == musicCategoryId) return true;
    final ch = channelTitle ?? '';
    if (RegExp(r'\s-\sTopic$').hasMatch(ch) || RegExp(r'vevo', caseSensitive: false).hasMatch(ch)) return true;
    final t = title ?? '';
    return RegExp(r'\((?:official\s*)?(?:music\s*video|audio|lyrics?|lyrical)', caseSensitive: false).hasMatch(t);
  }

  /// Splits `"Artist - Title (Official Video)"` style titles. Topic channels
  /// (`"Artist - Topic"`) already have clean titles.
  static ({String title, String artist}) splitTitle(String rawTitle, String channelTitle) {
    final cleanTitle = LyricsService.sanitize(unescapeHtml(rawTitle).replaceAll(_junk, '')).trim();
    final channelArtist = cleanArtistName(channelTitle);
    if (RegExp(r'\s-\sTopic$').hasMatch(channelTitle)) {
      return (title: cleanTitle, artist: channelArtist);
    }
    final dash = RegExp(r'\s[-–—]\s').firstMatch(cleanTitle);
    if (dash != null) {
      final left = cleanTitle.substring(0, dash.start).trim();
      final right = cleanTitle.substring(dash.end).trim();
      if (left.isNotEmpty && right.isNotEmpty) return (title: right, artist: left);
    }
    return (title: cleanTitle.isEmpty ? unescapeHtml(rawTitle) : cleanTitle, artist: channelArtist);
  }

  /// ISO-8601 duration (`PT1H2M3S`) → seconds.
  static int? parseIsoDuration(String? iso) {
    if (iso == null) return null;
    final m = RegExp(r'^P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$').firstMatch(iso);
    if (m == null) return null;
    int g(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
    final total = g(1) * 86400 + g(2) * 3600 + g(3) * 60 + g(4);
    return total == 0 ? null : total;
  }

  static Track trackFrom({
    required String videoId,
    required String rawTitle,
    required String channelTitle,
    int? durationSec,
    String? imageUrl,
    String? year,
  }) {
    final split = splitTitle(rawTitle, channelTitle);
    return Track(
      id: videoId,
      source: TrackSource.youtube,
      title: split.title,
      artist: split.artist,
      album: 'YouTube',
      durationSec: durationSec,
      year: year,
      imageUrl: imageUrl ?? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      webUrl: 'https://www.youtube.com/watch?v=$videoId',
    );
  }
}
