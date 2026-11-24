import '../models/track.dart';
import '../youtube/youtube_source.dart';
import 'innertube_client.dart';
import 'innertube_parser.dart';

class MixException implements Exception {
  MixException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// YouTube Music Mix / endless radio engine.
///
/// - Seed → YouTube `videoId` (YouTube tracks directly; JioSaavn/Spotify
///   tracks via a `"<title> <artist> audio"` search).
/// - First page: InnerTube `next` with `RDAMVM<videoId>` (YouTube Music radio),
///   falling back to `RD<videoId>` (classic mix) when empty.
/// - Refill: follow `nextRadioContinuationData`; when a radio runs dry, start
///   a new radio seeded from the most recent track, so the queue never ends.
class MixEngine {
  MixEngine({required InnerTubeClient innertube, required YouTubeSource youtube})
      : _innertube = innertube,
        _youtube = youtube;

  final InnerTubeClient _innertube;
  final YouTubeSource _youtube;

  static String musicRadioId(String videoId) => 'RDAMVM$videoId';
  static String videoMixId(String videoId) => 'RD$videoId';

  Future<String?> seedVideoId(Track seed) async {
    if (seed.source == TrackSource.youtube) return seed.id;
    final results = await _youtube.search('${seed.title} ${seed.artist} audio', limit: 1);
    return results.isEmpty ? null : results.first.id;
  }

  /// Starts a mix and loads its first page ([MixSession.initialTracks]).
  Future<MixSession> start(Track seed) async {
    final videoId = await seedVideoId(seed);
    if (videoId == null) throw MixException('Couldn\'t find "${seed.title}" on YouTube to start a mix.');
    final session = MixSession._(this, seed, videoId);
    await session._loadFirst();
    if (session.initialTracks.isEmpty) throw MixException('YouTube returned an empty mix for "${seed.title}".');
    return session;
  }

  Future<MixPage> _radio(String videoId) async {
    var page = InnerTubeParser.parseNext(
      await _innertube.next(videoId: videoId, playlistId: musicRadioId(videoId)),
    );
    if (page.tracks.isEmpty) {
      page = InnerTubeParser.parseNext(
        await _innertube.next(videoId: videoId, playlistId: videoMixId(videoId)),
      );
    }
    return page;
  }

  Future<MixPage> _continue(String token) async =>
      InnerTubeParser.parseNext(await _innertube.next(continuation: token));
}

/// A running mix. Call [more] to refill; results are de-duplicated across
/// pages by video id and by normalised "title|artist".
class MixSession {
  MixSession._(this._engine, this.seed, this.seedVideoId);

  final MixEngine _engine;
  final Track seed;
  final String seedVideoId;

  final Set<String> _seenIds = {};
  final Set<String> _seenKeys = {};
  String? _continuation;
  String _lastVideoId = '';
  List<Track> _initial = const [];
  int _reseeds = 0;

  static const int maxReseeds = 20;

  String get playlistId => MixEngine.musicRadioId(seedVideoId);
  String get title => '${seed.title} Mix';
  List<Track> get initialTracks => _initial;

  static String _key(Track t) =>
      '${t.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '')}|${t.artist.toLowerCase()}';

  /// Marks [tracks] as already queued (e.g. the seed itself).
  void markSeen(Iterable<Track> tracks) {
    for (final t in tracks) {
      if (t.source == TrackSource.youtube) _seenIds.add(t.id);
      _seenKeys.add(_key(t));
    }
  }

  List<Track> _fresh(List<Track> tracks) {
    final out = <Track>[];
    for (final t in tracks) {
      if (_seenIds.contains(t.id) || _seenKeys.contains(_key(t))) continue;
      _seenIds.add(t.id);
      _seenKeys.add(_key(t));
      out.add(t);
    }
    if (out.isNotEmpty) _lastVideoId = out.last.id;
    return out;
  }

  Future<void> _loadFirst() async {
    _seenIds.add(seedVideoId);
    markSeen([seed]);
    final page = await _engine._radio(seedVideoId);
    _continuation = page.continuation;
    _initial = _fresh(page.tracks);
  }

  /// Next batch of unseen tracks. Never returns empty while YouTube answers:
  /// exhausted radios are re-seeded from the latest track (endless radio).
  Future<List<Track>> more() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      MixPage page;
      final token = _continuation;
      if (token != null) {
        page = await _engine._continue(token);
      } else {
        if (_reseeds >= maxReseeds || _lastVideoId.isEmpty) return const [];
        _reseeds++;
        page = await _engine._radio(_lastVideoId);
      }
      _continuation = page.continuation;
      final fresh = _fresh(page.tracks);
      if (fresh.isNotEmpty) return fresh;
      if (page.continuation == null && token == null) return const [];
    }
    return const [];
  }
}
