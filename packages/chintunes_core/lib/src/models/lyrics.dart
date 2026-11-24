class LyricLine {
  const LyricLine(this.time, this.text);

  final Duration time;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is LyricLine && other.time == time && other.text == text;

  @override
  int get hashCode => Object.hash(time, text);

  @override
  String toString() => 'LyricLine($time, $text)';
}

/// Port of `LyricsData` from chinTunes-cli.
class Lyrics {
  const Lyrics({this.plain, this.synced = const [], this.source = 'UNKNOWN'});

  final String? plain;
  final List<LyricLine> synced;
  final String source;

  bool get hasSynced => synced.isNotEmpty;
  bool get isEmpty => !hasSynced && (plain == null || plain!.trim().isEmpty);

  /// Index of the active karaoke line for [position], or -1 before the first line.
  int activeIndex(Duration position) {
    var lo = 0, hi = synced.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (synced[mid].time <= position) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }
}
