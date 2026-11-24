import 'dart:convert';

import 'package:chintunes_core/chintunes_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Shape of `GET youtube/v3/videos?myRating=like` (trimmed).
const likedJson = {
  'kind': 'youtube#videoListResponse',
  'nextPageToken': 'PAGE2',
  'items': [
    {
      'id': 'BddP6PYo2gs',
      'snippet': {
        'title': 'Kesariya (From "Brahmastra")',
        'channelTitle': 'Arijit Singh - Topic',
        'categoryId': '10',
        'publishedAt': '2022-07-17T00:00:00Z',
        'thumbnails': {
          'high': {'url': 'https://i.ytimg.com/vi/BddP6PYo2gs/hqdefault.jpg'},
        },
      },
      'contentDetails': {'duration': 'PT2M53S'},
    },
    {
      'id': 'dQw4w9WgXcQ',
      'snippet': {
        'title': 'Rick Astley - Never Gonna Give You Up (Official Music Video)',
        'channelTitle': 'RickAstleyVEVO',
        'categoryId': '10',
      },
      'contentDetails': {'duration': 'PT3M33S'},
    },
    {
      'id': 'vlog123',
      'snippet': {'title': 'My trip to Goa', 'channelTitle': 'Some Vlogger', 'categoryId': '22'},
      'contentDetails': {'duration': 'PT12M'},
    },
  ],
};

void main() {
  group('YouTubeLibraryMapper', () {
    test('Topic channel keeps the title and cleans the artist', () {
      final s = YouTubeLibraryMapper.splitTitle('Kesariya', 'Arijit Singh - Topic');
      expect(s.title, 'Kesariya');
      expect(s.artist, 'Arijit Singh');
    });

    test('"Artist - Title (Official Music Video)" is split and cleaned', () {
      final s = YouTubeLibraryMapper.splitTitle('Rick Astley - Never Gonna Give You Up (Official Music Video)', 'RickAstleyVEVO');
      expect(s.artist, 'Rick Astley');
      expect(s.title, 'Never Gonna Give You Up');
    });

    test('ISO-8601 durations', () {
      expect(YouTubeLibraryMapper.parseIsoDuration('PT2M53S'), 173);
      expect(YouTubeLibraryMapper.parseIsoDuration('PT1H2M3S'), 3723);
      expect(YouTubeLibraryMapper.parseIsoDuration('PT12M'), 720);
      expect(YouTubeLibraryMapper.parseIsoDuration('P0D'), isNull);
    });
  });

  group('YouTubeAccountClient', () {
    test('likedVideos calls videos.list(myRating=like) and tags music', () async {
      late Uri requested;
      final client = MockClient((req) async {
        requested = req.url;
        return http.Response(jsonEncode(likedJson), 200, headers: {'content-type': 'application/json'});
      });
      final page = await YouTubeAccountClient(client).likedVideos();

      expect(requested.path, endsWith('/youtube/v3/videos'));
      expect(requested.queryParameters['myRating'], 'like');
      expect(requested.queryParametersAll['part'], containsAll(['snippet', 'contentDetails']));
      expect(page.nextPageToken, 'PAGE2');
      expect(page.items.length, 3);

      final kesariya = page.items[0];
      expect(kesariya.isMusic, isTrue);
      expect(kesariya.track.artist, 'Arijit Singh');
      expect(kesariya.track.durationSec, 173);
      expect(kesariya.track.year, '2022');

      expect(page.items[1].isMusic, isTrue);
      expect(page.items[1].track.title, 'Never Gonna Give You Up');
      expect(page.items[2].isMusic, isFalse);
    });

    test('myPlaylists calls playlists.list(mine=true)', () async {
      late Uri requested;
      final client = MockClient((req) async {
        requested = req.url;
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'PL1',
                'snippet': {'title': 'Gym', 'channelTitle': 'Me'},
                'contentDetails': {'itemCount': 12},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final playlists = await YouTubeAccountClient(client).myPlaylists();
      expect(requested.queryParameters['mine'], 'true');
      expect(playlists.single.title, 'Gym');
      expect(playlists.single.songCount, 12);
      expect(playlists.single.source, TrackSource.youtube);
    });
  });

  group('TakeoutHistoryParser', () {
    const takeout = '''
[
  {"header":"YouTube Music","title":"Watched Kesariya","titleUrl":"https://music.youtube.com/watch?v=BddP6PYo2gs",
   "subtitles":[{"name":"Arijit Singh - Topic","url":"https://www.youtube.com/channel/x"}],
   "time":"2024-05-02T10:00:00.000Z","products":["YouTube"]},
  {"header":"YouTube","title":"Watched My trip to Goa","titleUrl":"https://www.youtube.com/watch?v=vlog123",
   "subtitles":[{"name":"Some Vlogger"}],"time":"2024-05-01T09:00:00.000Z"},
  {"header":"YouTube","title":"Watched a video that has been removed","time":"2024-04-01T09:00:00.000Z"},
  {"header":"YouTube","title":"Watched Buy now","titleUrl":"https://www.youtube.com/watch?v=ad1",
   "details":[{"name":"From Google Ads"}],"time":"2024-04-02T09:00:00.000Z"}
]''';

    test('parses plays, strips "Watched", skips ads and removed videos', () {
      final entries = TakeoutHistoryParser.parse(takeout);
      expect(entries.map((e) => e.track.id), ['BddP6PYo2gs', 'vlog123']);
      expect(entries.first.track.title, 'Kesariya');
      expect(entries.first.track.artist, 'Arijit Singh');
      expect(entries.first.isMusic, isTrue);
      expect(entries.first.origin, 'takeout');
      expect(entries.first.playedAt, DateTime.utc(2024, 5, 2, 10));
      expect(entries.last.isMusic, isFalse);
    });

    test('musicOnly filter', () {
      expect(TakeoutHistoryParser.parse(takeout, musicOnly: true).map((e) => e.track.id), ['BddP6PYo2gs']);
    });

    test('rejects non-array JSON', () {
      expect(() => TakeoutHistoryParser.parse('{"a":1}'), throwsFormatException);
    });
  });
}
