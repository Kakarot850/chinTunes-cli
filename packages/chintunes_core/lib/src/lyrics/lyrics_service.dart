import '../jiosaavn/jiosaavn_client.dart';
import '../models/lyrics.dart';
import '../models/track.dart';
import 'lrclib_client.dart';

/// Hierarchical lyrics lookup (port of `LyricsEngine.find_lyrics`):
///
/// 1. LRCLIB synced (exact match with duration, then search) per artist variant
/// 2. JioSaavn studio plain lyrics (only for JioSaavn tracks with lyrics)
/// 3. LRCLIB plain
///
/// The CLI's `syncedlyrics` cascade (Musixmatch / NetEase / Genius) is not
/// ported yet — see PROGRESS.md Phase 4.
class LyricsService {
  LyricsService({required LrclibClient lrclib, required JioSaavnClient jiosaavn})
      : _lrclib = lrclib,
        _jiosaavn = jiosaavn;

  final LrclibClient _lrclib;
  final JioSaavnClient _jiosaavn;
  final Map<String, Lyrics?> _cache = {};

  static final List<RegExp> _junk = [
    RegExp(r'\(official[^)]*\)', caseSensitive: false),
    RegExp(r'\[official[^\]]*\]', caseSensitive: false),
    RegExp(r'\(audio[^)]*\)', caseSensitive: false),
    RegExp(r'\[audio[^\]]*\]', caseSensitive: false),
    RegExp(r'\(music\s+video\)', caseSensitive: false),
    RegExp(r'\(lyric[^)]*\)', caseSensitive: false),
    RegExp(r'\[lyric[^\]]*\]', caseSensitive: false),
    RegExp(r'\(video\)', caseSensitive: false),
  ];

  /// Port of `LyricsEngine.sanitize`.
  static String sanitize(String text) {
    var out = text;
    for (final r in _junk) {
      out = out.replaceAll(r, '');
    }
    return out.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Port of `get_artist_variants`: full string first, then each split artist.
  static List<String> artistVariants(String artist) {
    if (artist.trim().isEmpty) return const [];
    final variants = <String>[artist.trim()];
    final tokens = artist.split(
      RegExp(r'[,/&]|\s+feat\.?\s+|\s+ft\.?\s+|\s+with\s+', caseSensitive: false),
    );
    for (final t in tokens.map((t) => t.trim()).where((t) => t.isNotEmpty)) {
      if (!variants.contains(t)) variants.add(t);
    }
    return variants;
  }

  Future<Lyrics?> find(Track track) async {
    if (_cache.containsKey(track.uid)) return _cache[track.uid];
    final result = await _find(track);
    _cache[track.uid] = result;
    return result;
  }

  Future<Lyrics?> _find(Track track) async {
    final title = sanitize(track.title);
    // Cap variants: each costs up to 2 LRCLIB requests.
    final variants = artistVariants(track.artist).take(3).toList();
    Lyrics? plainFallback;

    for (final artist in variants) {
      try {
        if (track.durationSec != null) {
          final exact = await _lrclib.getExact(title: title, artist: artist, durationSec: track.durationSec!);
          if (exact != null && exact.hasSynced) return exact;
          plainFallback ??= exact;
        }
        final searched = await _lrclib.search(title: title, artist: artist);
        if (searched != null && searched.hasSynced) return searched;
        plainFallback ??= searched;
      } catch (_) {
        // Network/parse errors for one variant must not abort the cascade.
      }
    }

    if (track.source == TrackSource.jiosaavn && track.hasLyrics) {
      try {
        final plain = await _jiosaavn.lyrics(track.id);
        if (plain != null && plain.trim().length > 10) {
          return Lyrics(plain: plain, source: 'JIOSAAVN');
        }
      } catch (_) {}
    }
    return plainFallback;
  }
}
