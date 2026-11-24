import 'dart:convert';

import 'package:chintunes_core/chintunes_core.dart';
import 'package:test/test.dart';

import 'support/fixture_adapter.dart';

void main() {
  Map<String, dynamic> load(String name) => Map<String, dynamic>.from(jsonDecode(fixture(name)) as Map);

  group('InnerTubePlayerClient.parseAudio (visionOS live capture)', () {
    test('keeps audio-only itags with direct urls, drops video', () {
      final streams = InnerTubePlayerClient.parseAudio(load('yt_player_visionos.json'));
      expect(streams.map((s) => s.itag), [139, 140, 249, 250, 251]);
      final opus = streams.firstWhere((s) => s.itag == 249);
      expect(opus.isOpus, isTrue);
      expect(opus.container, 'webm');
      expect(opus.bitrateKbps, 54); // averageBitrate 53957
      expect(opus.sizeBytes, 1161567);
      final aac = streams.firstWhere((s) => s.itag == 140);
      expect(aac.codec, startsWith('mp4a'));
      expect(aac.container, 'mp4');
    });

    test('selection per data mode on real itags', () {
      final streams = InnerTubePlayerClient.parseAudio(load('yt_player_visionos.json'));
      expect(StreamSelector.pickYouTube(streams, DataMode.ultraSaver)!.itag, 249);
      expect(StreamSelector.pickYouTube(streams, DataMode.balanced)!.itag, 250);
      expect(StreamSelector.pickYouTube(streams, DataMode.high)!.itag, 251);
    });

    test('bot check is detected', () {
      final err = InnerTubePlayerClient.playabilityError(load('yt_player_bot_check.json'))!;
      expect(err.isBotCheck, isTrue);
      expect(InnerTubePlayerClient.playabilityError(load('yt_player_visionos.json')), isNull);
    });
  });

  group('InnerTubePlayerClient.audioStreams', () {
    test('fetches visitorData, then calls player as VISIONOS with it', () async {
      final adapter = FixtureAdapter(fallback: (o) {
        if (o.path.endsWith('/visitor_id')) return fixture('yt_visitor_id.json');
        if (o.path.endsWith('/player')) return fixture('yt_player_visionos.json');
        return null;
      });
      final client = InnerTubePlayerClient(dio: fixtureDio(adapter, baseUrl: InnerTubePlayerClient.baseUrl));
      final streams = await client.audioStreams('BddP6PYo2gs');
      expect(streams, hasLength(5));

      final playerReq = adapter.requests.firstWhere((r) => r.path.endsWith('/player'));
      final body = jsonDecode(playerReq.data as String) as Map<String, dynamic>;
      final c = (body['context'] as Map)['client'] as Map;
      expect(c['clientName'], 'VISIONOS');
      expect(c['visitorData'], 'CgtmaXkxLXJFOVFQOCiu8ZbYBjIKCgJJThIEGgAgHA%3D%3D');
      expect(body['videoId'], 'BddP6PYo2gs');
      expect(playerReq.headers['X-Goog-Visitor-Id'], c['visitorData']);
      expect(playerReq.headers['X-Youtube-Client-Name'], '101');

      // Visitor id is cached for the next track.
      await client.audioStreams('ElZfdU54Cp8');
      expect(adapter.requests.where((r) => r.path.endsWith('/visitor_id')), hasLength(1));
    });

    test('bot check → refreshes visitor id once, then succeeds', () async {
      var players = 0;
      final adapter = FixtureAdapter(fallback: (o) {
        if (o.path.endsWith('/visitor_id')) return fixture('yt_visitor_id.json');
        if (o.path.endsWith('/player')) {
          players++;
          return players == 1 ? fixture('yt_player_bot_check.json') : fixture('yt_player_visionos.json');
        }
        return null;
      });
      final client = InnerTubePlayerClient(dio: fixtureDio(adapter, baseUrl: InnerTubePlayerClient.baseUrl));
      expect(await client.audioStreams('x'), isNotEmpty);
      expect(adapter.requests.where((r) => r.path.endsWith('/visitor_id')), hasLength(2));
    });

    test('persistent bot check → readable StreamResolveException', () async {
      final adapter = FixtureAdapter(fallback: (o) {
        if (o.path.endsWith('/visitor_id')) return fixture('yt_visitor_id.json');
        return fixture('yt_player_bot_check.json');
      });
      final client = InnerTubePlayerClient(dio: fixtureDio(adapter, baseUrl: InnerTubePlayerClient.baseUrl));
      expect(
        () => client.audioStreams('x'),
        throwsA(isA<StreamResolveException>().having((e) => e.message, 'message', contains('not a bot'))),
      );
    });
  });
}
