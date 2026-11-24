import 'package:chintunes_core/chintunes_core.dart';
import 'package:test/test.dart';

import 'support/fixture_adapter.dart';

void main() {
  late FixtureAdapter adapter;
  late JioSaavnClient client;

  setUp(() {
    adapter = FixtureAdapter(calls: {
      'search.getResults': 'search_songs.json',
      'search.getAlbumResults': 'search_albums.json',
      'search.getPlaylistResults': 'search_playlists.json',
      'search.getArtistResults': 'search_artists.json',
      'song.getDetails': 'song_details.json',
      'playlist.getDetails': 'playlist.json',
      'content.getTrending': 'trending.json',
      'webapi.getLaunchData': 'launch.json',
    }, fallback: (o) {
      final call = o.queryParameters['__call'];
      final type = o.queryParameters['type'];
      if (call == 'webapi.get' && type == 'album') return fixture('album.json');
      if (call == 'webapi.get' && type == 'artist') return fixture('artist.json');
      if (call == 'lyrics.getLyrics') return '{"lyrics":"Line one<br>Line &quot;two&quot;<br/>Line three"}';
      return null;
    });
    client = JioSaavnClient(dio: fixtureDio(adapter));
  });

  test('sends CLI-equivalent query parameters', () async {
    await client.searchSongs('tum hi ho', limit: 5);
    final q = adapter.requests.single.queryParameters;
    expect(q['__call'], 'search.getResults');
    expect(q['q'], 'tum hi ho');
    expect(q['n'], 5);
    expect(q['ctx'], 'wap6dot0');
    expect(q['api_version'], '4');
    expect(q['_format'], 'json');
    expect(adapter.requests.single.path, '/api.php');
  });

  test('searchSongs parses tracks with decrypted media, hi-res art and clean artist', () async {
    final songs = await client.searchSongs('tum hi ho');
    expect(songs, isNotEmpty);
    final t = songs.first;
    expect(t.id, 'aRZbUYD7');
    expect(t.title, 'Tum Hi Ho');
    expect(t.source, TrackSource.jiosaavn);
    // B-001: artist comes from artistMap, not "Mithoon, Arijit Singh - Aashiqui 2".
    expect(t.artist, 'Mithoon, Arijit Singh');
    expect(t.album, 'Aashiqui 2');
    expect(t.durationSec, 262);
    expect(t.has320, isTrue);
    expect(t.hasLyrics, isTrue);
    expect(t.imageUrl, contains('500x500'));
    expect(t.mediaUrl, startsWith('https://aac.saavncdn.com/'));
    expect(t.mediaUrl, endsWith('_96.mp4'));
  });

  test('collection searches map to typed summaries', () async {
    final albums = await client.searchAlbums('aashiqui');
    expect(albums.first.type, CollectionType.album);
    expect(albums.first.title, 'Aashiqui 2');
    expect(albums.first.token, '-iNdCmFNV9o_');

    final playlists = await client.searchPlaylists('romantic');
    expect(playlists.first.type, CollectionType.playlist);
    expect(playlists.first.id, '903166403');

    final artists = await client.searchArtists('arijit');
    expect(artists.first.type, CollectionType.artist);
    expect(artists.first.title, 'Arijit Singh');
    expect(artists.first.token, 'LlRWpHzy3Hk_');
  });

  test('album and playlist details include playable tracks', () async {
    final album = await client.album(token: '-iNdCmFNV9o_');
    expect(album, isNotNull);
    expect(album!.summary.title, 'Aashiqui 2');
    expect(album.tracks, isNotEmpty);
    expect(album.tracks.every((t) => t.mediaUrl != null), isTrue);

    final playlist = await client.playlist(id: '903166403');
    expect(playlist!.summary.title, 'Best Of Romance - Hindi');
    expect(playlist.tracks.length, 3);
    expect(adapter.requests.last.queryParameters['listid'], '903166403');
  });

  test('artist detail exposes top songs and albums', () async {
    final artist = await client.artist(token: 'LlRWpHzy3Hk_');
    expect(artist!.summary.title, 'Arijit Singh');
    expect(artist.tracks, isNotEmpty);
    expect(artist.related.first.type, CollectionType.album);
  });

  test('songDetails refreshes media url by id', () async {
    final songs = await client.songDetails(['aRZbUYD7']);
    expect(songs.single.mediaUrl, isNotNull);
    expect(adapter.requests.single.queryParameters['pids'], 'aRZbUYD7');
  });

  test('homeFeed merges launch modules (ordered) and trending', () async {
    final feed = await client.homeFeed();
    expect(feed.trending, isNotEmpty);
    expect(feed.sections, isNotEmpty);
    final titles = feed.sections.map((s) => s.title).toList();
    expect(titles.first, 'Trending Now'); // module position 1
    expect(titles, contains('Top Charts'));
    for (final s in feed.sections) {
      for (final item in s.items) {
        expect(item.imageUrl, anyOf(isNull, startsWith('https://')));
      }
    }
  });

  test('homeFeed survives a failing launch endpoint', () async {
    final failing = FixtureAdapter(
      calls: {'content.getTrending': 'trending.json'},
      fallback: (_) => 'not json',
    );
    final c = JioSaavnClient(dio: fixtureDio(failing));
    final feed = await c.homeFeed();
    expect(feed.sections, isEmpty);
    expect(feed.trending, isNotEmpty);
  });

  test('lyrics converts <br> and unescapes entities', () async {
    final lyrics = await client.lyrics('aRZbUYD7');
    expect(lyrics, 'Line one\nLine "two"\nLine three');
  });
}
