import 'package:chintunes_core/chintunes_core.dart';
import 'package:test/test.dart';

import 'support/fixture_adapter.dart';

void main() {
  group('LrcParser', () {
    test('parses 2- and 3-digit fractions and sorts', () {
      final lines = LrcParser.parse('[00:15.55] B\n[00:11.20] A\n[01:02.123]C');
      expect(lines, [
        const LyricLine(Duration(seconds: 11, milliseconds: 200), 'A'),
        const LyricLine(Duration(seconds: 15, milliseconds: 550), 'B'),
        const LyricLine(Duration(minutes: 1, seconds: 2, milliseconds: 123), 'C'),
      ]);
    });

    test('expands multi-stamp lines and skips metadata/blank lines', () {
      final lines = LrcParser.parse('[ar:Someone]\n[00:01.00][00:30.00]Chorus\n[00:05.00]\n');
      expect(lines.map((l) => l.text), ['Chorus', 'Chorus']);
      expect(lines.last.time, const Duration(seconds: 30));
    });

    test('stripTimestamps returns plain text', () {
      expect(LrcParser.stripTimestamps('[00:01.00]Hello\n[00:02.00]World'), 'Hello\nWorld');
      expect(LrcParser.stripTimestamps(null), isNull);
    });

    test('Lyrics.activeIndex finds the karaoke line', () {
      final lyrics = Lyrics(synced: LrcParser.parse('[00:01.00]a\n[00:05.00]b\n[00:09.00]c'));
      expect(lyrics.activeIndex(Duration.zero), -1);
      expect(lyrics.activeIndex(const Duration(seconds: 1)), 0);
      expect(lyrics.activeIndex(const Duration(seconds: 7)), 1);
      expect(lyrics.activeIndex(const Duration(minutes: 3)), 2);
    });
  });

  group('LyricsService helpers (CLI parity)', () {
    test('sanitize strips video/audio junk', () {
      expect(LyricsService.sanitize('Tum Hi Ho (Official Video) [Lyric Video]'), 'Tum Hi Ho');
    });

    test('artistVariants splits feat/ft/&/,', () {
      expect(
        LyricsService.artistVariants('Mithoon, Arijit Singh feat. X & Y'),
        ['Mithoon, Arijit Singh feat. X & Y', 'Mithoon', 'Arijit Singh', 'X', 'Y'],
      );
    });
  });

  group('LyricsService.find', () {
    const track = Track(
      id: 'aRZbUYD7',
      source: TrackSource.jiosaavn,
      title: 'Tum Hi Ho',
      artist: 'Arijit Singh',
      durationSec: 262,
      hasLyrics: true,
    );

    test('prefers LRCLIB synced lyrics', () async {
      final lrcAdapter = FixtureAdapter(fallback: (o) {
        if (o.path.endsWith('/api/get')) return null; // 404 → fall through to search
        if (o.path.endsWith('/api/search')) return fixture('lrclib_search.json');
        return null;
      });
      final service = LyricsService(
        lrclib: LrclibClient(dio: fixtureDio(lrcAdapter, baseUrl: LrclibClient.baseUrl)),
        jiosaavn: JioSaavnClient(dio: fixtureDio(FixtureAdapter())),
      );
      final lyrics = await service.find(track);
      expect(lyrics, isNotNull);
      expect(lyrics!.hasSynced, isTrue);
      expect(lyrics.source, 'LRCLIB (Synced)');
      expect(lyrics.synced.first.text, 'Hum tere bin ab reh nahi sakte');
    });

    test('falls back to JioSaavn plain lyrics when LRCLIB has nothing', () async {
      final service = LyricsService(
        lrclib: LrclibClient(
          dio: fixtureDio(FixtureAdapter(fallback: (_) => '[]'), baseUrl: LrclibClient.baseUrl),
        ),
        jiosaavn: JioSaavnClient(
          dio: fixtureDio(FixtureAdapter(fallback: (_) => '{"lyrics":"Hum tere bin<br>ab reh nahi sakte"}')),
        ),
      );
      final lyrics = await service.find(track);
      expect(lyrics?.source, 'JIOSAAVN');
      expect(lyrics?.plain, 'Hum tere bin\nab reh nahi sakte');
    });
  });
}
