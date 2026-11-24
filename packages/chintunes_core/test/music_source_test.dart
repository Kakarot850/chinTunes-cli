import 'package:chintunes_core/chintunes_core.dart';
import 'package:test/test.dart';

import 'support/fake_youtube.dart';
import 'support/fixture_adapter.dart';

void main() {
  const ytTrack = Track(id: 'yt1', source: TrackSource.youtube, title: 'Tum Hi Ho (Official Video)', artist: 'Arijit Singh');
  const saavnTrack = Track(
    id: 'aRZbUYD7',
    source: TrackSource.jiosaavn,
    title: 'Tum Hi Ho',
    artist: 'Arijit Singh',
    mediaUrl: 'https://aac.saavncdn.com/430/abc_96.mp4',
  );

  group('SearchService + MusicSource', () {
    late FixtureAdapter adapter;
    late FakeYouTubeSource yt;
    late SearchService search;

    setUp(() {
      adapter = FixtureAdapter(calls: {'search.getResults': 'search_songs.json'});
      yt = FakeYouTubeSource(searchResults: const [Track(id: 'y', source: TrackSource.youtube, title: 'Y')]);
      search = SearchService(jiosaavn: JioSaavnClient(dio: fixtureDio(adapter)), youtube: yt);
    });

    test('YouTube only: no JioSaavn request, 20 YouTube results requested', () async {
      final r = await search.search('tum hi ho', source: MusicSource.youtube);
      expect(adapter.requests, isEmpty);
      expect(r.songs, isEmpty);
      expect(r.youtube.single.id, 'y');
    });

    test('JioSaavn only: no YouTube search', () async {
      final r = await search.search('tum hi ho', source: MusicSource.jiosaavn);
      expect(yt.searched, isEmpty);
      expect(r.songs, isNotEmpty);
      expect(r.youtube, isEmpty);
    });

    test('Auto: both', () async {
      final r = await search.search('tum hi ho');
      expect(r.songs, isNotEmpty);
      expect(r.youtube, isNotEmpty);
    });
  });

  group('StreamResolver + MusicSource', () {
    late FixtureAdapter adapter;
    late FakeYouTubeSource yt;
    late StreamResolver resolver;

    setUp(() {
      adapter = FixtureAdapter(calls: {'search.getResults': 'search_songs.json'});
      yt = FakeYouTubeSource(searchResults: const [Track(id: 'match1', source: TrackSource.youtube, title: 'm')]);
      resolver = StreamResolver(jiosaavn: JioSaavnClient(dio: fixtureDio(adapter)), youtube: yt, dataMode: DataMode.high);
    });

    test('YouTube preference plays JioSaavn tracks through a YouTube match', () async {
      resolver.sourcePreference = MusicSource.youtube;
      final s = await resolver.resolve(saavnTrack);
      expect(yt.searched.single, 'Tum Hi Ho Arijit Singh audio');
      expect(yt.resolved.single, 'match1');
      expect(s.sourceLabel, 'YouTube');
    });

    test('JioSaavn preference matches YouTube tracks on JioSaavn (title cleaned)', () async {
      resolver.sourcePreference = MusicSource.jiosaavn;
      final s = await resolver.resolve(ytTrack);
      expect(adapter.requests.single.queryParameters['q'], 'Tum Hi Ho Arijit Singh');
      expect(s.uri.host, 'aac.saavncdn.com');
      expect(s.sourceLabel, 'JioSaavn (matched)');
      expect(yt.resolved, isEmpty);
    });

    test('JioSaavn preference falls back to YouTube when no title matches', () async {
      resolver.sourcePreference = MusicSource.jiosaavn;
      const other = Track(id: 'yt2', source: TrackSource.youtube, title: 'Completely Different Song', artist: 'X');
      final s = await resolver.resolve(other);
      expect(s.sourceLabel, 'YouTube');
      expect(yt.resolved.single, 'yt2');
    });

    test('Auto keeps each track on its own source', () async {
      expect((await resolver.resolve(saavnTrack)).sourceLabel, 'JioSaavn');
      expect((await resolver.resolve(ytTrack)).sourceLabel, 'YouTube');
      expect(adapter.requests, isEmpty);
    });
  });
}
