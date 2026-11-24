import 'package:chintunes_core/chintunes_core.dart';
import 'package:test/test.dart';

import 'support/fake_youtube.dart';
import 'support/fixture_adapter.dart';

void main() {
  group('PlaylistImporter.parseUrl', () {
    test('Spotify playlist / album (share text, ?si= params)', () {
      final p = PlaylistImporter.parseUrl(
        'Check this out! https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=abc123',
      )!;
      expect(p.service, PlaylistService.spotify);
      expect(p.kind, RemoteKind.playlist);
      expect(p.id, '37i9dQZF1DXcBWIGoYBM5M');
      expect(PlaylistImporter.parseUrl('https://open.spotify.com/intl-de/album/4aawyAB9vmqN3uQ7FjRGTy')!.kind,
          RemoteKind.album);
      expect(PlaylistImporter.parseUrl('https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT'), isNull);
    });

    test('Deezer (with locale), Apple Music, JioSaavn, YouTube', () {
      final dz = PlaylistImporter.parseUrl('https://www.deezer.com/en/playlist/3155776842')!;
      expect((dz.service, dz.id), (PlaylistService.deezer, '3155776842'));

      final am = PlaylistImporter.parseUrl(
        'https://music.apple.com/us/playlist/todays-hits/pl.f4d106fed2bd41149aaacabb233eb5eb',
      )!;
      expect((am.service, am.id), (PlaylistService.appleMusic, 'pl.f4d106fed2bd41149aaacabb233eb5eb'));

      final js = PlaylistImporter.parseUrl(
        'https://www.jiosaavn.com/featured/best-of-romance-hindi/SBKnUgjNeMIwkg5tVhI3fw__',
      )!;
      expect((js.service, js.id), (PlaylistService.jiosaavn, 'SBKnUgjNeMIwkg5tVhI3fw__'));

      final yt = PlaylistImporter.parseUrl('https://music.youtube.com/playlist?list=PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG')!;
      expect((yt.service, yt.id), (PlaylistService.youtube, 'PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG'));
      expect(PlaylistImporter.parseUrl('https://www.youtube.com/watch?v=abc&list=RDabc'), isNull); // auto-mix
      expect(PlaylistImporter.parseUrl('just some text'), isNull);
    });

    test('PlaylistRef JSON round-trip', () {
      final ref = PlaylistImporter.parseUrl('https://www.deezer.com/album/302127')!;
      final back = PlaylistRef.fromJson(Map<dynamic, dynamic>.from(ref.toJson()));
      expect((back.service, back.kind, back.id), (PlaylistService.deezer, RemoteKind.album, '302127'));
    });
  });

  group('service parsers (live-captured fixtures)', () {
    test('Spotify embed', () {
      final ref = PlaylistImporter.parseUrl('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M')!;
      final p = PlaylistImporter.parseSpotifyEmbed(fixture('spotify_embed_playlist.html'), ref);
      expect(p.title, 'Today’s Top Hits');
      expect(p.tracks, hasLength(3));
      final t = p.tracks.first;
      expect(t.source, TrackSource.spotify);
      expect(t.id, '4HCOHRCSQelz2GPX8iTamO');
      expect(t.artist, startsWith('Justice, Tame Impala, SZA')); // NBSP normalised
      expect(t.durationSec, 225);
      expect(p.tracks[1].title, 'Housewife');
      expect(p.imageUrl, startsWith('https://i.scdn.co/image/'));
    });

    test('Deezer playlist + next page', () async {
      final adapter = FixtureAdapter(fallback: (o) {
        final u = o.uri.toString();
        if (u.contains('/tracks?index=2')) return fixture('deezer_playlist_tracks_page2.json');
        if (u.endsWith('/playlist/3155776842')) return fixture('deezer_playlist.json');
        return null;
      });
      final importer = PlaylistImporter(
        jiosaavn: JioSaavnClient(dio: fixtureDio(FixtureAdapter())),
        youtube: FakeYouTubeSource(),
        dio: fixtureDio(adapter, baseUrl: ''),
      );
      final p = await importer.importUrl('https://www.deezer.com/en/playlist/3155776842');
      expect(p.title, 'Top Worldwide');
      expect(p.tracks.map((t) => t.title), ['Boston', "Choosin' Texas", 'BbY WOW', 'Housewife']);
      expect(p.tracks.first.source, TrackSource.deezer);
      expect(p.tracks.first.artist, 'STELLA LEFTY');
      expect(p.tracks.first.durationSec, 170);
      expect(p.tracks.first.imageUrl, startsWith('https://'));
    });

    test('Apple Music page', () {
      final ref = PlaylistImporter.parseUrl(
        'https://music.apple.com/us/playlist/todays-hits/pl.f4d106fed2bd41149aaacabb233eb5eb',
      )!;
      final p = PlaylistImporter.parseAppleMusicPage(fixture('apple_playlist.html'), ref);
      expect(p.title, 'Today’s Hits');
      expect(p.tracks.map((t) => t.title), ['stupid song', 'Housewife', 'Stop The Wedding!']);
      final t = p.tracks.first;
      expect(t.source, TrackSource.appleMusic);
      expect(t.id, '1889992115');
      expect(t.artist, 'Olivia Rodrigo');
      expect(t.album, 'you seem pretty sad for a girl so in love');
      expect(t.durationSec, 210);
      expect(t.imageUrl, endsWith('/500x500bb.jpg'));
    });

    test('JioSaavn playlist link via token', () async {
      final adapter = FixtureAdapter(fallback: (o) {
        if (o.queryParameters['__call'] == 'webapi.get' && o.queryParameters['type'] == 'playlist') {
          expect(o.queryParameters['token'], 'SBKnUgjNeMIwkg5tVhI3fw__');
          return fixture('playlist.json');
        }
        return null;
      });
      final importer = PlaylistImporter(jiosaavn: JioSaavnClient(dio: fixtureDio(adapter)), youtube: FakeYouTubeSource());
      final p = await importer.importUrl('https://www.jiosaavn.com/featured/best-of-romance-hindi/SBKnUgjNeMIwkg5tVhI3fw__');
      expect(p.title, 'Best Of Romance - Hindi');
      expect(p.tracks, hasLength(3));
      expect(p.tracks.first.source, TrackSource.jiosaavn);
    });

    test('unsupported link → readable ImportException', () async {
      final importer = PlaylistImporter(
        jiosaavn: JioSaavnClient(dio: fixtureDio(FixtureAdapter())),
        youtube: FakeYouTubeSource(),
        dio: fixtureDio(FixtureAdapter(), baseUrl: ''),
      );
      expect(() => importer.importUrl('https://tidal.com/browse/playlist/abc'), throwsA(isA<ImportException>()));
    });
  });

  group('PlaylistDiff', () {
    Track t(String id) => Track(id: id, source: TrackSource.spotify, title: id);

    test('added / removed / kept by uid, in remote order', () {
      final d = PlaylistDiff.compute([t('a'), t('b'), t('c')], [t('b'), t('d'), t('a'), t('e')]);
      expect(d.added.map((x) => x.id), ['d', 'e']);
      expect(d.removed.map((x) => x.id), ['c']);
      expect(d.kept, 2);
      expect(d.summary, '+2 new, −1 removed');
      expect(PlaylistDiff.compute([t('a')], [t('a')]).summary, 'Up to date');
    });
  });

  test('metadata-only sources play through a YouTube match with a clean query', () async {
    final yt = FakeYouTubeSource(searchResults: const [
      Track(id: 'v1', source: TrackSource.youtube, title: 'x', durationSec: 225),
    ]);
    final resolver = StreamResolver(jiosaavn: JioSaavnClient(dio: fixtureDio(FixtureAdapter())), youtube: yt);
    const deezer = Track(
      id: '1',
      source: TrackSource.deezer,
      title: 'Flower In A Hurricane (feat. Tame Impala) [From GTAVI: Original Score]',
      artist: 'Justice, Tame Impala, SZA, King Gizzard',
      durationSec: 225,
    );
    final s = await resolver.resolve(deezer);
    expect(yt.searched.single, 'Flower In A Hurricane Justice Tame Impala audio');
    expect(s.sourceLabel, 'YouTube');
    expect(TrackSource.deezer.isMetadataOnly, isTrue);
    expect(TrackSource.appleMusic.label, 'Apple Music');
  });
}
