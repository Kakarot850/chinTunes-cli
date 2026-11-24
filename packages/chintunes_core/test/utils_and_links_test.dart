import 'package:chintunes_core/chintunes_core.dart';
import 'package:test/test.dart';

void main() {
  group('cleanArtistName (CLI parity)', () {
    test('strips channel noise', () {
      expect(cleanArtistName('Arijit Singh - Topic'), 'Arijit Singh');
      expect(cleanArtistName('ArtistVEVO'), 'ArtistVEVO'); // needs whitespace, like the CLI
      expect(cleanArtistName('Artist VEVO'), 'Artist');
      expect(cleanArtistName('Coke Studio Official'), 'Coke Studio');
      expect(cleanArtistName(null), 'Unknown');
    });

    test('resolves "Release - Topic" from description bullet', () {
      expect(
        cleanArtistName('Release - Topic', description: 'Provided to YouTube\n\nSong · Real Artist\n'),
        'Real Artist',
      );
    });
  });

  test('unescapeHtml handles named, numeric and double-escaped entities', () {
    expect(unescapeHtml('Tu Mil Jaaye (From &quot;KING&quot;)'), 'Tu Mil Jaaye (From "KING")');
    expect(unescapeHtml('Rock &amp; Roll &#039;99'), "Rock & Roll '99");
    expect(unescapeHtml('&amp;quot;'), '&quot;');
  });

  test('upscaleSaavnImage upgrades size and forces https', () {
    expect(
      upscaleSaavnImage('http://c.saavncdn.com/430/Aashiqui-2-Hindi-2013-150x150.jpg'),
      'https://c.saavncdn.com/430/Aashiqui-2-Hindi-2013-500x500.jpg',
    );
    expect(upscaleSaavnImage('https://c.saavncdn.com/x-50x50.jpg'), 'https://c.saavncdn.com/x-500x500.jpg');
    expect(upscaleSaavnImage(''), isNull);
  });

  group('LinkRouter', () {
    test('JioSaavn links', () {
      final song = LinkRouter.parse('https://www.jiosaavn.com/song/tum-hi-ho/EToxUyFpcwQ')!;
      expect(song.source, TrackSource.jiosaavn);
      expect(song.type, CollectionType.song);
      expect(song.id, 'EToxUyFpcwQ');
      expect(LinkRouter.parse('https://www.jiosaavn.com/album/aashiqui-2/-iNdCmFNV9o_')!.type, CollectionType.album);
      expect(LinkRouter.parse('jiosaavn.com/featured/best-of-romance-hindi/SBKnUgjNeMIwkg')!.type,
          CollectionType.playlist);
      expect(LinkRouter.parse('https://www.jiosaavn.com/artist/arijit-singh-songs/LlRWpHzy3Hk_')!.type,
          CollectionType.artist);
    });

    test('YouTube links', () {
      expect(LinkRouter.parse('https://youtu.be/dQw4w9WgXcQ?si=x')!.id, 'dQw4w9WgXcQ');
      expect(LinkRouter.parse('https://music.youtube.com/watch?v=abc&list=PL1')!.type, CollectionType.song);
      final pl = LinkRouter.parse('https://www.youtube.com/playlist?list=PL123')!;
      expect(pl.type, CollectionType.playlist);
      expect(pl.id, 'PL123');
    });

    test('Spotify track links only', () {
      final t = LinkRouter.parse('https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT?si=1')!;
      expect(t.source, TrackSource.spotify);
      expect(t.id, '4cOdK2wGLETKBW3PvgPWqT');
      expect(LinkRouter.parse('https://open.spotify.com/playlist/xyz'), isNull);
    });

    test('plain text is not a link', () {
      expect(LinkRouter.looksLikeUrl('arijit singh'), isFalse);
      expect(LinkRouter.parse('arijit singh'), isNull);
    });
  });

  test('Track JSON round-trips through Hive-style untyped maps', () {
    const t = Track(
      id: 'aRZbUYD7',
      source: TrackSource.jiosaavn,
      title: 'Tum Hi Ho',
      artist: 'Arijit Singh',
      album: 'Aashiqui 2',
      durationSec: 262,
      has320: true,
      mediaUrl: 'https://aac.saavncdn.com/x_96.mp4',
    );
    final untyped = Map<dynamic, dynamic>.from(t.toJson());
    final back = Track.fromJson(untyped);
    expect(back, t);
    expect(back.durationSec, 262);
    expect(back.has320, isTrue);
    expect(back.mediaUrl, t.mediaUrl);
    expect(back.uid, 'jiosaavn:aRZbUYD7');
  });
}
