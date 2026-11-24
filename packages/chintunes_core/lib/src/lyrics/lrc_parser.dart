import '../models/lyrics.dart';

/// LRC parsing (ports `parse_lrc_to_sylt`, `strip_lrc_timestamps` and the
/// terminal player's karaoke parser).
///
/// Handles `[mm:ss]`, `[mm:ss.xx]`, `[mm:ss.xxx]`, multiple stamps on one
/// line (`[00:12.00][01:30.50]chorus`) and ignores metadata tags (`[ar:...]`).
abstract final class LrcParser {
  static final RegExp _stamp = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

  static List<LyricLine> parse(String? lrc) {
    if (lrc == null || lrc.isEmpty) return const [];
    final out = <LyricLine>[];
    for (final rawLine in lrc.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      final stamps = <Duration>[];
      var rest = line;
      while (true) {
        final m = _stamp.matchAsPrefix(rest);
        if (m == null) break;
        final mins = int.parse(m[1]!);
        final secs = int.parse(m[2]!);
        final frac = m[3];
        var millis = 0;
        if (frac != null) {
          // "5" -> 500ms, "50" -> 500ms, "500" -> 500ms
          millis = int.parse(frac.padRight(3, '0'));
        }
        stamps.add(Duration(minutes: mins, seconds: secs, milliseconds: millis));
        rest = rest.substring(m.end);
      }
      final text = rest.trim();
      if (stamps.isEmpty || text.isEmpty) continue;
      for (final t in stamps) {
        out.add(LyricLine(t, text));
      }
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  static bool looksSynced(String? text) =>
      text != null && RegExp(r'\[\d{1,3}:\d{2}').hasMatch(text);

  /// Plain text from synced LRC (port of `strip_lrc_timestamps`).
  static String? stripTimestamps(String? synced) {
    final lines = parse(synced).map((l) => l.text).toList();
    return lines.isEmpty ? null : lines.join('\n');
  }
}
