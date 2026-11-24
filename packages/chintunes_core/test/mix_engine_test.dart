import 'dart:convert';

import 'package:chintunes_core/chintunes_core.dart';
import 'package:test/test.dart';

import 'support/fake_youtube.dart';
import 'support/fixture_adapter.dart';

void main() {
  Map<String, dynamic> load(String name) => Map<String, dynamic>.from(jsonDecode(fixture(name)) as Map);

  group('InnerTubeParser', () {
    test('parses the first RDAMVM page (live capture) incl. wrapper renderers', () {
      final page = InnerTubeParser.parseNext(load('ytm_mix_first.json'));
      expect(page.tracks.map((t) => t.id), [
        'BddP6PYo2gs',
        'ElZfdU54Cp8',
        'hXh35CtnSyU',
        'HqUeSjsYLNU',
        'SAcpESN_Fk4',
        '3pz_bHeZLkg', // from playlistPanelVideoWrapperRenderer.primaryRenderer
      ]);
      expect(page.tracks.map((t) => t.id), isNot(contains('COUNTERPART')));
      expect(page.continuation, 'CONT_TOKEN_1');

      final first = page.tracks.first;
      expect(first.title, 'Kesariya (From "Brahmastra")');
      expect(first.artist, 'Arijit Singh');
      expect(first.durationSec, 173);
      expect(first.source, TrackSource.youtube);
      expect(first.imageUrl, startsWith('https://i.ytimg.com/vi/BddP6PYo2gs/'));
    });

    test('parses continuation pages', () {
      final page = InnerTubeParser.parseNext(load('ytm_mix_continuation.json'));
      expect(page.tracks.length, 4);
      expect(page.continuation, 'CONT_TOKEN_2');
    });

    test('clock parsing', () {
      expect(InnerTubeParser.parseClock('2:53'), 173);
      expect(InnerTubeParser.parseClock('1:02:03'), 3723);
      expect(InnerTubeParser.parseClock('live'), isNull);
    });

    test('mix playlist ids', () {
      expect(MixEngine.musicRadioId('abc'), 'RDAMVMabc');
      expect(MixEngine.videoMixId('abc'), 'RDabc');
    });
  });

  group('MixEngine / MixSession', () {
    late FixtureAdapter adapter;
    late MixEngine engine;
    late FakeYouTubeSource yt;

    setUp(() {
      adapter = FixtureAdapter(fallback: (o) {
        if (!o.path.endsWith('/youtubei/v1/next')) return null;
        final body = o.data?.toString() ?? '';
        return body.contains('"continuation"') ? fixture('ytm_mix_continuation.json') : fixture('ytm_mix_first.json');
      });
      yt = FakeYouTubeSource(searchResults: const [
        Track(id: 'BddP6PYo2gs', source: TrackSource.youtube, title: 'Kesariya', artist: 'Arijit Singh'),
      ]);
      engine = MixEngine(
        innertube: InnerTubeClient(dio: fixtureDio(adapter, baseUrl: InnerTubeClient.baseUrl)),
        youtube: yt,
      );
    });

    test('YouTube seed: requests RDAMVM<id> and excludes the seed', () async {
      const seed = Track(id: 'BddP6PYo2gs', source: TrackSource.youtube, title: 'Kesariya', artist: 'Arijit Singh');
      final session = await engine.start(seed);
      final body = jsonDecode(adapter.requests.first.data as String) as Map<String, dynamic>;
      expect(body['playlistId'], 'RDAMVMBddP6PYo2gs');
      expect(body['videoId'], 'BddP6PYo2gs');
      expect((body['context'] as Map)['client'], containsPair('clientName', 'WEB_REMIX'));
      expect(session.initialTracks.map((t) => t.id), ['ElZfdU54Cp8', 'hXh35CtnSyU', 'HqUeSjsYLNU', 'SAcpESN_Fk4', '3pz_bHeZLkg']);
      expect(yt.searched, isEmpty);
    });

    test('JioSaavn seed is matched on YouTube first', () async {
      const seed = Track(id: 'abc', source: TrackSource.jiosaavn, title: 'Kesariya', artist: 'Arijit Singh');
      final session = await engine.start(seed);
      expect(yt.searched.single, 'Kesariya Arijit Singh audio');
      expect(session.seedVideoId, 'BddP6PYo2gs');
    });

    test('more() follows the continuation and de-duplicates across pages', () async {
      const seed = Track(id: 'BddP6PYo2gs', source: TrackSource.youtube, title: 'Kesariya', artist: 'Arijit Singh');
      final session = await engine.start(seed);
      final more = await session.more();
      expect(more.map((t) => t.id), ['dCfYh10G1BA', '3D8bmo5Dlwc', 'XEjLoHdbVeE']); // ElZfdU54Cp8 deduped
      final lastBody = jsonDecode(adapter.requests.last.data as String) as Map<String, dynamic>;
      expect(lastBody['continuation'], 'CONT_TOKEN_1');
      expect(lastBody.containsKey('playlistId'), isFalse);
    });

    test('empty mix throws a readable error', () async {
      final empty = MixEngine(
        innertube: InnerTubeClient(
          dio: fixtureDio(FixtureAdapter(fallback: (_) => '{}'), baseUrl: InnerTubeClient.baseUrl),
        ),
        youtube: yt,
      );
      expect(
        () => empty.start(const Track(id: 'x', source: TrackSource.youtube, title: 'X')),
        throwsA(isA<MixException>()),
      );
    });
  });
}
