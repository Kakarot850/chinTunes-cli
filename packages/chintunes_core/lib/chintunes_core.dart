/// chinTunes core: catalog clients, stream resolution, data saver, mixes,
/// downloads, YouTube account sync, lyrics and queue logic.
///
/// Pure Dart (no Flutter imports) so it can be unit-tested with `dart test`.
library;

export 'src/account/takeout_history.dart';
export 'src/account/youtube_account_client.dart';
export 'src/account/youtube_library_mapper.dart';
export 'src/catalog_service.dart';
export 'src/data/artwork_sizer.dart';
export 'src/data/data_mode.dart';
export 'src/data/data_usage.dart';
export 'src/data/stream_selection.dart';
export 'src/downloads/byte_fetcher.dart';
export 'src/downloads/download_manager.dart';
export 'src/downloads/download_store.dart';
export 'src/downloads/download_task.dart';
export 'src/http/dio_factory.dart';
export 'src/jiosaavn/jiosaavn_client.dart';
export 'src/jiosaavn/jiosaavn_crypto.dart';
export 'src/jiosaavn/jiosaavn_parser.dart';
export 'src/link_router.dart';
export 'src/lyrics/lrc_parser.dart';
export 'src/lyrics/lrclib_client.dart';
export 'src/lyrics/lyrics_service.dart';
export 'src/mix/innertube_client.dart';
export 'src/mix/innertube_parser.dart';
export 'src/mix/mix_engine.dart';
export 'src/models/collection.dart';
export 'src/models/home_feed.dart';
export 'src/models/lyrics.dart';
export 'src/models/resolved_stream.dart';
export 'src/models/search_results.dart';
export 'src/models/track.dart';
export 'src/playback/playback_queue.dart';
export 'src/search_service.dart';
export 'src/spotify/spotify_client.dart';
export 'src/stream_resolver.dart';
export 'src/util/artist_name.dart';
export 'src/util/html_text.dart';
export 'src/util/image_url.dart';
export 'src/youtube/youtube_explode_source.dart';
export 'src/youtube/youtube_source.dart';
