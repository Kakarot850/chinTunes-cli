import 'package:chintunes_core/chintunes_core.dart';
import 'package:test/test.dart';

import 'support/fake_youtube.dart';
import 'support/fixture_adapter.dart';

AudioStreamCandidate c(int itag, int kbps, {String codec = 'opus', String container = 'webm'}) =>
    AudioStreamCandidate(
      itag: itag,
      bitrateKbps: kbps,
      codec: codec,
      container: container,
      url: Uri.parse('https://rr.googlevideo.com/?itag=$itag'),
    );

void main() {
  // What youtube_explode typically reports as `manifest.audioOnly`.
  final full = [
    c(139, 48, codec: 'mp4a.40.5', container: 'mp4'),
    c(140, 129, codec: 'mp4a.40.2', container: 'mp4'),
    c(249, 51),
    c(250, 68),
    c(251, 135),
  ];

  group('StreamSelector.pickYouTube', () {
    test('Ultra Saver → Opus itag 249 (~50 kbps)', () {
      expect(StreamSelector.pickYouTube(full, DataMode.ultraSaver)!.itag, 249);
    });

    test('Balanced → Opus itag 250 (~70 kbps)', () {
      expect(StreamSelector.pickYouTube(full, DataMode.balanced)!.itag, 250);
    });

    test('High → Opus itag 251 (~160 kbps)', () {
      expect(StreamSelector.pickYouTube(full, DataMode.high)!.itag, 251);
    });

    test('Ultra Saver prefers any Opus over AAC 139 when 249 is missing', () {
      final noLow = full.where((s) => s.itag != 249).toList();
      expect(StreamSelector.pickYouTube(noLow, DataMode.ultraSaver)!.itag, 250);
    });

    test('falls back to AAC only when no Opus rendition exists', () {
      final aacOnly = full.where((s) => !s.isOpus).toList();
      expect(StreamSelector.pickYouTube(aacOnly, DataMode.ultraSaver)!.itag, 139);
      expect(StreamSelector.pickYouTube(aacOnly, DataMode.high)!.itag, 140);
    });

    test('unknown itags: closest Opus bitrate to the mode target', () {
      final odd = [c(600, 32), c(601, 64), c(602, 150), c(700, 96, codec: 'mp4a.40.2', container: 'mp4')];
      expect(StreamSelector.pickYouTube(odd, DataMode.ultraSaver)!.itag, 601); // |64-50| < |32-50|
      expect(StreamSelector.pickYouTube(odd, DataMode.high)!.itag, 602);
    });

    test('empty manifest → null', () {
      expect(StreamSelector.pickYouTube(const [], DataMode.high), isNull);
    });
  });

  group('JioSaavn bitrate per mode', () {
    test('Ultra 96 / Balanced 160 / High 320 with 160 fallback', () {
      expect(StreamSelector.jioSaavnKbps(DataMode.ultraSaver, has320: true), 96);
      expect(StreamSelector.jioSaavnKbps(DataMode.balanced, has320: true), 160);
      expect(StreamSelector.jioSaavnKbps(DataMode.high, has320: true), 320);
      expect(StreamSelector.jioSaavnKbps(DataMode.high, has320: false), 160);
    });

    test('resolver passes the data mode to YouTube and per-call overrides win', () async {
      final yt = FakeYouTubeSource();
      final resolver = StreamResolver(
        jiosaavn: JioSaavnClient(dio: fixtureDio(FixtureAdapter())),
        youtube: yt,
        dataMode: DataMode.ultraSaver,
      );
      const t = Track(id: 'v1', source: TrackSource.youtube, title: 't');
      await resolver.resolve(t);
      await resolver.resolve(t, mode: DataMode.high);
      expect(yt.resolvedModes, [DataMode.ultraSaver, DataMode.high]);
    });
  });

  group('ArtworkSizer (Ultra Saver thumbnails)', () {
    test('JioSaavn 500x500 → 150x150', () {
      expect(
        ArtworkSizer.adapt('https://c.saavncdn.com/430/Aashiqui-2-Hindi-2013-500x500.jpg', DataMode.ultraSaver),
        'https://c.saavncdn.com/430/Aashiqui-2-Hindi-2013-150x150.jpg',
      );
    });

    test('YouTube thumbnails → mqdefault', () {
      expect(
        ArtworkSizer.adapt('https://i.ytimg.com/vi/BddP6PYo2gs/hq720.jpg?sqp=abc&rs=xyz', DataMode.ultraSaver),
        'https://i.ytimg.com/vi/BddP6PYo2gs/mqdefault.jpg',
      );
    });

    test('Google user content → 120px', () {
      expect(
        ArtworkSizer.adapt('https://lh3.googleusercontent.com/abc=w544-h544-l90-rj', DataMode.ultraSaver),
        'https://lh3.googleusercontent.com/abc=w120-h120-l90-rj',
      );
    });

    test('other modes and local files are untouched', () {
      const url = 'https://c.saavncdn.com/x-500x500.jpg';
      expect(ArtworkSizer.adapt(url, DataMode.high), url);
      expect(ArtworkSizer.adapt('file:///data/cover.jpg', DataMode.ultraSaver), 'file:///data/cover.jpg');
    });
  });

  group('NetworkPolicy', () {
    test('no prefetch on cellular in Ultra Saver only', () {
      expect(NetworkPolicy.allowPrefetch(DataMode.ultraSaver, NetworkKind.cellular), isFalse);
      expect(NetworkPolicy.allowPrefetch(DataMode.ultraSaver, NetworkKind.wifi), isTrue);
      expect(NetworkPolicy.allowPrefetch(DataMode.balanced, NetworkKind.cellular), isTrue);
      expect(NetworkPolicy.allowPrefetch(DataMode.high, NetworkKind.offline), isFalse);
    });
  });

  group('DataUsageMeter', () {
    test('saved = High baseline minus streamed; local plays save everything', () {
      final meter = DataUsageMeter();
      // 100 s at 50 kbps vs 160 kbps baseline.
      meter.recordPlayback(actualKbps: 50, baselineKbps: 160, listened: const Duration(seconds: 100), fromLocal: false);
      expect(meter.snapshot.sessionUsedBytes, 625000);
      expect(meter.snapshot.sessionSavedBytes, 1375000);
      // Offline/cached: 0 used, full baseline saved.
      meter.recordPlayback(actualKbps: 320, baselineKbps: 320, listened: const Duration(seconds: 10), fromLocal: true);
      expect(meter.snapshot.sessionUsedBytes, 625000);
      expect(meter.snapshot.sessionSavedBytes, 1375000 + 400000);
    });

    test('totals persist through toJson/fromJson; session starts at zero', () {
      final meter = DataUsageMeter(totalSavedBytes: 10, totalUsedBytes: 5)
        ..recordPlayback(actualKbps: 96, baselineKbps: 320, listened: const Duration(seconds: 8), fromLocal: false);
      final restored = DataUsageMeter.fromJson(meter.toJson());
      expect(restored.snapshot.totalSavedBytes, meter.snapshot.totalSavedBytes);
      expect(restored.snapshot.totalUsedBytes, meter.snapshot.totalUsedBytes);
      expect(restored.snapshot.sessionSavedBytes, 0);
    });

    test('High baseline per source', () {
      expect(StreamSelector.highBaselineKbps(const Track(id: 'a', source: TrackSource.jiosaavn, title: 'a', has320: true)), 320);
      expect(StreamSelector.highBaselineKbps(const Track(id: 'a', source: TrackSource.jiosaavn, title: 'a')), 160);
      expect(StreamSelector.highBaselineKbps(const Track(id: 'a', source: TrackSource.youtube, title: 'a')), 160);
    });
  });
}
