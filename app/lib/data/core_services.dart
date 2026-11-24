import 'package:chintunes_core/chintunes_core.dart';

/// Composition root for the pure-Dart core (one instance per app).
class CoreServices {
  CoreServices._({
    required this.jiosaavn,
    required this.youtube,
    required this.spotify,
    required this.resolver,
    required this.search,
    required this.catalog,
    required this.lyrics,
    required this.mixes,
    required this.usage,
  });

  factory CoreServices.create({DataMode dataMode = DataMode.balanced, DataUsageMeter? usage}) {
    final jiosaavn = JioSaavnClient();
    final youtube = YoutubeExplodeSource();
    final spotify = SpotifyClient();
    return CoreServices._(
      jiosaavn: jiosaavn,
      youtube: youtube,
      spotify: spotify,
      resolver: StreamResolver(jiosaavn: jiosaavn, youtube: youtube, dataMode: dataMode),
      search: SearchService(jiosaavn: jiosaavn, youtube: youtube),
      catalog: CatalogService(jiosaavn: jiosaavn, youtube: youtube, spotify: spotify),
      lyrics: LyricsService(lrclib: LrclibClient(), jiosaavn: jiosaavn),
      mixes: MixEngine(innertube: InnerTubeClient(), youtube: youtube),
      usage: usage ?? DataUsageMeter(),
    );
  }

  final JioSaavnClient jiosaavn;
  final YouTubeSource youtube;
  final SpotifyClient spotify;
  final StreamResolver resolver;
  final SearchService search;
  final CatalogService catalog;
  final LyricsService lyrics;
  final MixEngine mixes;
  final DataUsageMeter usage;
}
