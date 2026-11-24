import 'package:chintunes_core/chintunes_core.dart';
import 'package:test/test.dart';

import 'support/fake_youtube.dart';
import 'support/fixture_adapter.dart';

void main() {
  const saavn = Track(
    id: 'aRZbUYD7',
    source: TrackSource.jiosaavn,
    title: 'Tum Hi Ho',
    mediaUrl: 'https://aac.saavncdn.com/430/abc_96.mp4',
    has320: true,
  );

  group('StreamResolver', () {
    late FakeYouTubeSource yt;
    late FixtureAdapter adapter;
    late StreamResolver resolver;

    setUp(() {
      yt = FakeYouTubeSource(searchResults: const [
        Track(id: 'dQw4w9WgXcQ', source: TrackSource.youtube, title: 'Match', durationSec: 213),
      ]);
      adapter = FixtureAdapter(calls: {'song.getDetails': 'song_details.json'});
      resolver = StreamResolver(
        jiosaavn: JioSaavnClient(dio: fixtureDio(adapter)),
        youtube: yt,
        dataMode: DataMode.high,
        fileExists: (p) => p == '/data/offline/song.m4a',
      );
    });

    test('JioSaavn: 320 kbps when flagged', () async {
      final s = await resolver.resolve(saavn);
      expect(s.uri.toString(), 'https://aac.saavncdn.com/430/abc_320.mp4');
      expect(s.bitrateKbps, 320);
      expect(s.badge, 'JioSaavn · 320 kbps AAC');
      expect(s.expires, isFalse);
    });

    test('JioSaavn: falls back to 160 when 320 is not flagged', () async {
      final s = await resolver.resolve(saavn.copyWith(has320: false));
      expect(s.uri.toString(), endsWith('_160.mp4'));
    });

    test('JioSaavn: honours lower data mode', () async {
      resolver.dataMode = DataMode.ultraSaver;
      final s = await resolver.resolve(saavn);
      expect(s.uri.toString(), endsWith('_96.mp4'));
    });

    test('offlineLookup (download manager) short-circuits the network', () async {
      resolver.offlineLookup = (t) => t.uid == saavn.uid ? '/data/offline/song.m4a' : null;
      final s = await resolver.resolve(saavn);
      expect(s.isLocal, isTrue);
      expect(adapter.requests, isEmpty);
      // Downloads force a network stream even when a copy exists.
      final net = await resolver.resolve(saavn, allowOffline: false);
      expect(net.isLocal, isFalse);
    });

    test('JioSaavn: refetches media url via song.getDetails when missing', () async {
      const bare = Track(id: 'aRZbUYD7', source: TrackSource.jiosaavn, title: 'Tum Hi Ho');
      final s = await resolver.resolve(bare);
      expect(s.uri.host, 'aac.saavncdn.com');
      expect(adapter.requests.single.queryParameters['__call'], 'song.getDetails');
    });

    test('offline copy wins over network', () async {
      final s = await resolver.resolve(saavn.copyWith(localPath: '/data/offline/song.m4a'));
      expect(s.isLocal, isTrue);
      expect(s.badge, 'Offline · M4A');
    });

    test('missing offline file falls back to network', () async {
      final s = await resolver.resolve(saavn.copyWith(localPath: '/gone.m4a'));
      expect(s.isLocal, isFalse);
    });

    test('YouTube tracks resolve via the YouTube source', () async {
      const t = Track(id: 'abc123', source: TrackSource.youtube, title: 'x');
      final s = await resolver.resolve(t);
      expect(yt.resolved, ['abc123']);
      expect(s.expires, isTrue);
    });

    test('Spotify tracks match on YouTube ("title artist audio")', () async {
      const t = Track(id: 'sp1', source: TrackSource.spotify, title: 'Never Gonna', artist: 'Rick');
      await resolver.resolve(t);
      expect(yt.searched.single, 'Never Gonna Rick audio');
      expect(yt.resolved.single, 'dQw4w9WgXcQ');
    });
  });

  group('SearchService', () {
    test('songs filter merges JioSaavn + YouTube', () async {
      final service = SearchService(
        jiosaavn: JioSaavnClient(dio: fixtureDio(FixtureAdapter(calls: {'search.getResults': 'search_songs.json'}))),
        youtube: FakeYouTubeSource(searchResults: const [Track(id: 'y', source: TrackSource.youtube, title: 'Y')]),
      );
      final r = await service.search('tum hi ho');
      expect(r.songs, isNotEmpty);
      expect(r.youtube.single.id, 'y');
      expect(r.errors, isEmpty);
    });

    test('one failing source is isolated', () async {
      final service = SearchService(
        jiosaavn: JioSaavnClient(dio: fixtureDio(FixtureAdapter(calls: {'search.getResults': 'search_songs.json'}))),
        youtube: FakeYouTubeSource(failSearch: true),
      );
      final r = await service.search('tum hi ho');
      expect(r.songs, isNotEmpty);
      expect(r.youtube, isEmpty);
      expect(r.errors.single, startsWith('YouTube'));
    });

    test('collections filter interleaves albums and playlists', () async {
      final service = SearchService(
        jiosaavn: JioSaavnClient(
          dio: fixtureDio(FixtureAdapter(calls: {
            'search.getAlbumResults': 'search_albums.json',
            'search.getPlaylistResults': 'search_playlists.json',
          })),
        ),
        youtube: FakeYouTubeSource(),
      );
      final r = await service.search('x', filter: SearchFilter.collections);
      expect(r.collections.map((c) => c.type).take(2), [CollectionType.album, CollectionType.playlist]);
    });

    test('blank query short-circuits', () async {
      final service = SearchService(
        jiosaavn: JioSaavnClient(dio: fixtureDio(FixtureAdapter())),
        youtube: FakeYouTubeSource(),
      );
      expect((await service.search('   ')).isEmpty, isTrue);
    });
  });
}
