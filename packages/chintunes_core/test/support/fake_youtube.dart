import 'package:chintunes_core/chintunes_core.dart';

class FakeYouTubeSource implements YouTubeSource {
  FakeYouTubeSource({this.searchResults = const [], this.failSearch = false, this.unplayable = const {}});

  final List<Track> searchResults;
  final bool failSearch;

  /// Video ids whose resolveAudio throws (e.g. age-restricted / blocked).
  final Set<String> unplayable;
  final List<String> searched = [];
  final List<String> resolved = [];
  final List<DataMode> resolvedModes = [];

  @override
  Future<List<Track>> search(String query, {int limit = 10}) async {
    searched.add(query);
    if (failSearch) throw StateError('youtube down');
    return searchResults.take(limit).toList();
  }

  @override
  Future<Track?> video(String videoId) async =>
      Track(id: videoId, source: TrackSource.youtube, title: 'Video $videoId');

  @override
  Future<ResolvedStream> resolveAudio(String videoId, {DataMode mode = DataMode.high}) async {
    resolved.add(videoId);
    resolvedModes.add(mode);
    if (unplayable.contains(videoId)) throw StreamResolveException('UNPLAYABLE $videoId');
    return ResolvedStream(
      uri: Uri.parse('https://rr1.googlevideo.com/videoplayback?id=$videoId'),
      sourceLabel: 'YouTube',
      bitrateKbps: mode.youtubeTargetKbps,
      codec: 'Opus',
      container: 'webm',
      expires: true,
    );
  }

  @override
  Future<MediaCollection?> playlist(String playlistId, {int limit = 200}) async => null;

  @override
  void close() {}
}
