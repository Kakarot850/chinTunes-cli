import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chintunes_core/chintunes_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/chintunes_audio_handler.dart';
import 'audio_cache.dart';
import 'core_services.dart';
import 'google_account.dart';
import 'library_store.dart';
import 'network_monitor.dart';
import 'playlist_sync.dart';

// ---------------------------------------------------------------- roots
// Overridden in main.dart (and in tests).

final coreServicesProvider = Provider<CoreServices>((ref) => throw UnimplementedError('override in main()'));
final libraryStoreProvider = Provider<LibraryStore>((ref) => throw UnimplementedError('override in main()'));
final audioHandlerProvider = Provider<ChinTunesAudioHandler>((ref) => throw UnimplementedError('override in main()'));
final downloadManagerProvider = Provider<DownloadManager>((ref) => throw UnimplementedError('override in main()'));
final audioCacheProvider = Provider<AudioCache>((ref) => throw UnimplementedError('override in main()'));
final networkMonitorProvider = Provider<NetworkMonitor>((ref) => throw UnimplementedError('override in main()'));

// ------------------------------------------------------ data saver

class DataModeNotifier extends Notifier<DataMode> {
  @override
  DataMode build() => ref.watch(libraryStoreProvider).dataMode();

  Future<void> set(DataMode mode) async {
    if (mode == state) return;
    state = mode;
    await ref.read(libraryStoreProvider).setDataMode(mode);
    await ref.read(audioHandlerProvider).setDataMode(mode);
  }
}

final dataModeNotifierProvider = NotifierProvider<DataModeNotifier, DataMode>(DataModeNotifier.new);

/// Read-only view (override this one in widget tests).
final dataModeProvider = Provider<DataMode>((ref) => ref.watch(dataModeNotifierProvider));

final dataUsageProvider = StreamProvider<DataUsageSnapshot>((ref) async* {
  final meter = ref.watch(coreServicesProvider).usage;
  yield meter.snapshot;
  yield* meter.changes;
});

final networkKindProvider = StreamProvider<NetworkKind>((ref) async* {
  final monitor = ref.watch(networkMonitorProvider);
  yield monitor.kind;
  yield* monitor.changes;
});

// ------------------------------------------------------- downloads

final downloadsProvider = StreamProvider<List<DownloadTask>>((ref) async* {
  final manager = ref.watch(downloadManagerProvider);
  yield manager.tasks;
  yield* manager.changes;
});

final downloadedIdsProvider = Provider<Set<String>>((ref) {
  final tasks = ref.watch(downloadsProvider).valueOrNull ?? const <DownloadTask>[];
  return tasks.where((t) => t.isCompleted).map((t) => t.uid).toSet();
});

final downloadTaskProvider = Provider.family<DownloadTask?, String>((ref, uid) {
  final tasks = ref.watch(downloadsProvider).valueOrNull ?? const <DownloadTask>[];
  for (final t in tasks) {
    if (t.uid == uid) return t;
  }
  return null;
});

/// Bytes on disk: offline downloads and the stream cache.
final storageUsageProvider = FutureProvider.autoDispose<({int downloads, int cache})>((ref) async {
  // Recompute when a download finishes or is deleted.
  ref.watch(downloadedIdsProvider);
  final downloads = await ref.watch(downloadManagerProvider).diskUsageBytes();
  final cache = await ref.watch(audioCacheProvider).sizeBytes();
  return (downloads: downloads, cache: cache);
});

// ------------------------------------------------ Google / YouTube

final accountProvider = NotifierProvider<GoogleAccountNotifier, AccountState>(GoogleAccountNotifier.new);

class MusicOnlyNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(libraryStoreProvider).youtubeMusicOnly();

  Future<void> set(bool value) async {
    state = value;
    await ref.read(libraryStoreProvider).setYoutubeMusicOnly(value);
  }
}

class MusicSourceNotifier extends Notifier<MusicSource> {
  @override
  MusicSource build() => ref.watch(libraryStoreProvider).musicSource();

  Future<void> set(MusicSource source) async {
    if (source == state) return;
    state = source;
    ref.read(coreServicesProvider).resolver.sourcePreference = source;
    await ref.read(libraryStoreProvider).setMusicSource(source);
  }
}

/// Settings → Music source (search + cross-source playback, B-037).
final musicSourceProvider = NotifierProvider<MusicSourceNotifier, MusicSource>(MusicSourceNotifier.new);

class AutoplayNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(libraryStoreProvider).autoplayEnabled();

  Future<void> set(bool value) async {
    state = value;
    await ref.read(libraryStoreProvider).setAutoplayEnabled(value);
  }
}

/// Settings → "Autoplay similar songs" when the queue runs out (B-038).
final autoplayProvider = NotifierProvider<AutoplayNotifier, bool>(AutoplayNotifier.new);

class StreamCacheNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(libraryStoreProvider).streamCacheEnabled();

  Future<void> set(bool value) async {
    state = value;
    await ref.read(libraryStoreProvider).setStreamCacheEnabled(value);
  }
}

/// Settings → "Stream cache" (LockCachingAudioSource for the current track).
final streamCacheProvider = NotifierProvider<StreamCacheNotifier, bool>(StreamCacheNotifier.new);

/// "Music only" filter for YouTube likes / history.
final musicOnlyProvider = NotifierProvider<MusicOnlyNotifier, bool>(MusicOnlyNotifier.new);

final ytLikedProvider = FutureProvider.autoDispose<List<TaggedTrack>>((ref) async {
  final signedIn = ref.watch(accountProvider.select((s) => s.signedIn));
  if (!signedIn) return const [];
  final client = await ref.read(accountProvider.notifier).client();
  if (client == null) return const [];
  return client.allLikedVideos();
});

final ytPlaylistsProvider = FutureProvider.autoDispose<List<CollectionSummary>>((ref) async {
  final signedIn = ref.watch(accountProvider.select((s) => s.signedIn));
  if (!signedIn) return const [];
  final client = await ref.read(accountProvider.notifier).client();
  if (client == null) return const [];
  return client.myPlaylists();
});

final ytPlaylistProvider = FutureProvider.autoDispose.family<MediaCollection, CollectionSummary>((ref, summary) async {
  final client = await ref.read(accountProvider.notifier).client();
  if (client == null) throw StateError('Sign in to open your YouTube playlists.');
  return client.playlist(summary);
});

/// Local plays + imported Google Takeout history, newest first.
final historyEntriesProvider = StreamProvider<List<HistoryEntry>>((ref) {
  final musicOnly = ref.watch(musicOnlyProvider);
  return ref.watch(libraryStoreProvider).watchCombinedHistory(musicOnly: musicOnly);
});

// ------------------------------------------------- playlist import / sync

final playlistSyncProvider = Provider<PlaylistSyncService>((ref) {
  final service = PlaylistSyncService(
    importer: ref.watch(coreServicesProvider).importer,
    store: ref.watch(libraryStoreProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

// ------------------------------------------------------ home radio feed

/// Home "Quick picks" + endless "More for you" (B-042): a YouTube Music radio
/// seeded from the most-played track, else the latest like, else trending.
/// [HomeRadioNotifier.loadMore] appends the next page as the user scrolls.
class HomeRadioNotifier extends AsyncNotifier<List<Track>> {
  MixSession? _session;
  bool _loadingMore = false;
  bool _exhausted = false;

  bool get isLoadingMore => _loadingMore;
  bool get exhausted => _exhausted;

  @override
  Future<List<Track>> build() async {
    _session = null;
    _exhausted = false;
    final store = ref.read(libraryStoreProvider);
    Track? seed;
    final top = store.topTracks(limit: 1);
    if (top.isNotEmpty) seed = top.first;
    if (seed == null) {
      final liked = store.likedTracks();
      if (liked.isNotEmpty) seed = liked.first;
    }
    if (seed == null) {
      final feed = await ref.watch(homeFeedProvider.future);
      if (feed.trending.isNotEmpty) seed = feed.trending.first;
    }
    if (seed == null) return const [];
    final session = await ref.read(coreServicesProvider).mixes.start(seed);
    _session = session;
    return session.initialTracks;
  }

  Future<void> loadMore() async {
    final session = _session;
    final current = state.valueOrNull;
    if (session == null || current == null || _loadingMore || _exhausted) return;
    _loadingMore = true;
    try {
      final more = await session.more();
      if (!identical(session, _session)) return;
      if (more.isEmpty) {
        _exhausted = true;
      } else {
        state = AsyncData([...current, ...more]);
      }
    } catch (_) {
      // Offline / InnerTube hiccup: the next scroll retries.
    } finally {
      _loadingMore = false;
    }
  }
}

final homeRadioProvider = AsyncNotifierProvider<HomeRadioNotifier, List<Track>>(HomeRadioNotifier.new);

// ------------------------------------------------------------ mixes

/// Seeds for the "Your Mixes" shelf: most played, then recent likes,
/// falling back to trending songs for new users.
final mixSeedsProvider = Provider<List<Track>>((ref) {
  final liked = ref.watch(likedTracksProvider).valueOrNull ?? const <Track>[];
  ref.watch(historyProvider); // recompute after plays
  final top = ref.read(libraryStoreProvider).topTracks(limit: 6);
  final seeds = <Track>[];
  final seen = <String>{};
  void add(Track t) {
    if (seeds.length < 6 && seen.add(t.uid)) seeds.add(t);
  }

  top.take(3).forEach(add);
  liked.take(3).forEach(add);
  top.skip(3).forEach(add);
  if (seeds.isEmpty) {
    final trending = ref.watch(homeFeedProvider).valueOrNull?.trending ?? const <Track>[];
    trending.take(4).forEach(add);
  }
  return seeds;
});

// ------------------------------------------------------------- catalog

final homeFeedProvider = FutureProvider<HomeFeed>((ref) {
  return ref.watch(coreServicesProvider).catalog.homeFeed();
});

final collectionProvider = FutureProvider.autoDispose.family<MediaCollection, CollectionSummary>((ref, summary) {
  return ref.watch(coreServicesProvider).catalog.open(summary);
});

final linkProvider = FutureProvider.autoDispose.family<MediaCollection, String>((ref, url) {
  return ref.watch(coreServicesProvider).catalog.openLink(url);
});

/// Family key is a record, so equality is structural.
final searchResultsProvider =
    FutureProvider.autoDispose.family<SearchResults, (String, SearchFilter)>((ref, request) async {
  final (query, filter) = request;
  // Keep recent result pages warm while the user flips filter chips.
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 2), link.close);
  ref.onDispose(timer.cancel);
  final source = ref.watch(musicSourceProvider); // re-run when the source changes
  return ref.watch(coreServicesProvider).search.search(query, filter: filter, source: source);
});

final lyricsProvider = FutureProvider.autoDispose.family<Lyrics?, Track>((ref, track) {
  return ref.watch(coreServicesProvider).lyrics.find(track);
});

// ------------------------------------------------------------- library

final likedTracksProvider = StreamProvider<List<Track>>((ref) {
  return ref.watch(libraryStoreProvider).watchLiked();
});

final likedIdsProvider = Provider<Set<String>>((ref) {
  final liked = ref.watch(likedTracksProvider).valueOrNull ?? const <Track>[];
  return liked.map((t) => t.uid).toSet();
});

final historyProvider = StreamProvider<List<Track>>((ref) {
  return ref.watch(libraryStoreProvider).watchHistory();
});

final playlistsProvider = StreamProvider<List<LocalPlaylist>>((ref) {
  return ref.watch(libraryStoreProvider).watchPlaylists();
});

final recentSearchesProvider = StreamProvider<List<String>>((ref) {
  return ref.watch(libraryStoreProvider).watchRecentSearches();
});

// -------------------------------------------------------------- player

final mediaItemProvider = StreamProvider<MediaItem?>((ref) {
  return ref.watch(audioHandlerProvider).mediaItem;
});

final playbackStateProvider = StreamProvider<PlaybackState>((ref) {
  return ref.watch(audioHandlerProvider).playbackState;
});

final queueProvider = StreamProvider<List<MediaItem>>((ref) {
  return ref.watch(audioHandlerProvider).queue;
});

/// Shared 200 ms position ticker. Consume it ONLY via a small StreamBuilder
/// (seek bar / progress line) so position ticks never rebuild whole screens.
final positionStreamProvider = Provider<Stream<Duration>>((ref) {
  return ref.watch(audioHandlerProvider).positionStream;
});

final isPlayingProvider = Provider<bool>((ref) {
  return ref.watch(playbackStateProvider.select((s) => s.valueOrNull?.playing ?? false));
});

final isBufferingProvider = Provider<bool>((ref) {
  return ref.watch(playbackStateProvider.select((s) {
    final p = s.valueOrNull?.processingState;
    return p == AudioProcessingState.loading || p == AudioProcessingState.buffering;
  }));
});

/// Dynamic tint extracted from the active cover art.
final artColorSchemeProvider = FutureProvider.family<ColorScheme?, String>((ref, url) async {
  try {
    final ImageProvider provider =
        url.startsWith('file:') ? FileImage(File(Uri.parse(url).toFilePath())) : CachedNetworkImageProvider(url);
    return await ColorScheme.fromImageProvider(
      provider: provider,
      brightness: Brightness.dark,
    );
  } catch (_) {
    return null;
  }
});

// --------------------------------------------------------- sleep timer

class SleepTimerState {
  const SleepTimerState({this.endsAt, this.endOfTrack = false});

  final DateTime? endsAt;
  final bool endOfTrack;

  bool get isActive => endsAt != null || endOfTrack;
}

class SleepTimerNotifier extends Notifier<SleepTimerState> {
  Timer? _timer;
  StreamSubscription<void>? _firedSub;

  @override
  SleepTimerState build() {
    final handler = ref.watch(audioHandlerProvider);
    _firedSub = handler.sleepFired.listen((_) => state = const SleepTimerState());
    ref.onDispose(() {
      _timer?.cancel();
      unawaited(_firedSub?.cancel());
    });
    return const SleepTimerState();
  }

  void start(Duration duration) {
    _clear();
    final handler = ref.read(audioHandlerProvider);
    _timer = Timer(duration, () {
      unawaited(handler.pause());
      state = const SleepTimerState();
    });
    state = SleepTimerState(endsAt: DateTime.now().add(duration));
  }

  void endOfTrack() {
    _clear();
    unawaited(ref.read(audioHandlerProvider).setPauseAtEndOfTrack(true));
    state = const SleepTimerState(endOfTrack: true);
  }

  void cancel() {
    _clear();
    state = const SleepTimerState();
  }

  void _clear() {
    _timer?.cancel();
    _timer = null;
    final handler = ref.read(audioHandlerProvider);
    if (handler.pauseAtEndOfTrack) unawaited(handler.setPauseAtEndOfTrack(false));
  }
}

final sleepTimerProvider = NotifierProvider<SleepTimerNotifier, SleepTimerState>(SleepTimerNotifier.new);
