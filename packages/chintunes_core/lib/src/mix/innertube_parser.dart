import '../models/track.dart';
import '../util/artist_name.dart';

/// One page of a mix / radio queue.
class MixPage {
  const MixPage({required this.tracks, this.continuation});

  final List<Track> tracks;

  /// Token for the next page (`nextRadioContinuationData`), null when exhausted.
  final String? continuation;
}

/// Parses InnerTube `next` responses (first page and continuations).
///
/// Uses a structural deep-walk for `playlistPanelVideoRenderer` instead of a
/// fixed path, because YouTube moves the panel between
/// `singleColumnMusicWatchNextResultsRenderer…playlistPanelRenderer.contents`
/// (first page) and `continuationContents.playlistPanelContinuation.contents`
/// (continuations), and sometimes wraps items in
/// `playlistPanelVideoWrapperRenderer` (only `primaryRenderer` is used;
/// `counterpart` song/video twins are skipped).
abstract final class InnerTubeParser {
  static MixPage parseNext(Map<String, dynamic> json) {
    final renderers = <Map<dynamic, dynamic>>[];
    String? radioToken;
    String? otherToken;
    void walk(Object? node) {
      if (node is Map) {
        for (final entry in node.entries) {
          final key = entry.key;
          final value = entry.value;
          if (key == 'playlistPanelVideoRenderer' && value is Map) {
            renderers.add(value);
          } else if (key == 'playlistPanelVideoWrapperRenderer' && value is Map) {
            walk(value['primaryRenderer']);
          } else if (key == 'nextRadioContinuationData' && value is Map) {
            radioToken ??= _nonEmpty(value['continuation']);
          } else if (key == 'nextContinuationData' && value is Map) {
            otherToken ??= _nonEmpty(value['continuation']);
          } else {
            walk(value);
          }
        }
      } else if (node is List) {
        for (final v in node) {
          walk(v);
        }
      }
    }

    walk(json);
    return MixPage(
      tracks: renderers.map(track).whereType<Track>().toList(),
      continuation: radioToken ?? otherToken,
    );
  }

  static String? _nonEmpty(Object? v) {
    final s = v?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }

  static List<Map<dynamic, dynamic>> _runs(Object? text) {
    if (text is! Map) return const [];
    final runs = text['runs'];
    return runs is List ? runs.whereType<Map<dynamic, dynamic>>().toList() : const [];
  }

  static String _text(Object? text) => _runs(text).map((r) => r['text']?.toString() ?? '').join().trim();

  static String? _pageType(Map<dynamic, dynamic> run) {
    final nav = run['navigationEndpoint'];
    if (nav is! Map) return null;
    final browse = nav['browseEndpoint'];
    if (browse is! Map) return null;
    final configs = browse['browseEndpointContextSupportedConfigs'];
    if (configs is! Map) return null;
    final music = configs['browseEndpointContextMusicConfig'];
    return music is Map ? music['pageType']?.toString() : null;
  }

  /// `"3:45"` / `"1:02:03"` → seconds.
  static int? parseClock(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final parts = text.trim().split(':').map(int.tryParse).toList();
    if (parts.any((p) => p == null)) return null;
    return parts.fold<int>(0, (acc, p) => acc * 60 + p!);
  }

  static String? _bestThumbnail(Object? thumbnail) {
    if (thumbnail is! Map) return null;
    final list = thumbnail['thumbnails'];
    if (list is! List || list.isEmpty) return null;
    final thumbs = list.whereType<Map<dynamic, dynamic>>().toList()
      ..sort((a, b) => ((a['width'] as num?) ?? 0).compareTo((b['width'] as num?) ?? 0));
    final url = thumbs.isEmpty ? null : thumbs.last['url']?.toString();
    if (url == null) return null;
    // Square Google-hosted art: request a 544px rendition.
    if (url.contains('googleusercontent.com')) {
      return url.replaceFirst(RegExp(r'=w\d+-h\d+[^/]*$'), '=w544-h544-l90-rj');
    }
    return url;
  }

  static Track? track(Map<dynamic, dynamic> r) {
    final id = r['videoId']?.toString();
    if (id == null || id.isEmpty) return null;
    final title = _text(r['title']);
    if (title.isEmpty) return null;

    final artists = <String>[];
    String? album;
    String? year;
    final byline = _runs(r['longBylineText']);
    for (final run in byline) {
      final text = run['text']?.toString().trim() ?? '';
      if (text.isEmpty || text == '•') continue;
      switch (_pageType(run)) {
        case 'MUSIC_PAGE_TYPE_ARTIST' || 'MUSIC_PAGE_TYPE_USER_CHANNEL':
          artists.add(text);
        case 'MUSIC_PAGE_TYPE_ALBUM':
          album = text;
        default:
          if (RegExp(r'^\d{4}$').hasMatch(text)) year = text;
      }
    }
    var artist = artists.join(', ');
    if (artist.isEmpty) artist = _text(r['shortBylineText']);
    if (artist.isEmpty && byline.isNotEmpty) artist = byline.first['text']?.toString() ?? '';

    final lengthRuns = _runs(r['lengthText']);
    return Track(
      id: id,
      source: TrackSource.youtube,
      title: title,
      artist: cleanArtistName(artist),
      album: album ?? 'YouTube Music',
      year: year,
      durationSec: parseClock(lengthRuns.isEmpty ? null : lengthRuns.first['text']?.toString()),
      imageUrl: _bestThumbnail(r['thumbnail']),
      webUrl: 'https://music.youtube.com/watch?v=$id',
    );
  }
}
