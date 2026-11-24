import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:chintunes_core/chintunes_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'audio/chintunes_audio_handler.dart';
import 'data/audio_cache.dart';
import 'data/core_services.dart';
import 'data/library_store.dart';
import 'data/network_monitor.dart';
import 'data/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  final store = await LibraryStore.open();
  final usage = DataUsageMeter.fromJson(store.dataUsage());
  final core = CoreServices.create(dataMode: store.dataMode(), usage: usage);
  // Persist data-saved totals as they change.
  usage.changes.listen((_) => unawaited(store.saveDataUsage(usage.toJson())));

  final docs = await getApplicationDocumentsDirectory();
  final cacheRoot = await getApplicationCacheDirectory();
  final cache = AudioCache(Directory('${cacheRoot.path}${Platform.pathSeparator}audio_cache'));
  await cache.ensure();
  unawaited(cache.prune());

  final downloads = DownloadManager(
    root: Directory('${docs.path}${Platform.pathSeparator}downloads'),
    store: store.downloadStore,
    resolve: (track, mode) => core.resolver.resolve(track, mode: mode, allowOffline: false),
    fetcher: DioByteFetcher(),
    currentMode: () => core.resolver.dataMode,
  );
  core.resolver.offlineLookup = downloads.offlinePath;
  await downloads.init();

  final network = await NetworkMonitor.start();

  final handler = await AudioService.init<ChinTunesAudioHandler>(
    builder: () => ChinTunesAudioHandler(
      resolver: core.resolver,
      onTrackStarted: (track) => unawaited(store.recordPlay(track)),
      localize: downloads.localize,
      cache: cache,
      allowPrefetch: () => NetworkPolicy.allowPrefetch(core.resolver.dataMode, network.kind),
      cacheEnabled: store.streamCacheEnabled,
      usage: usage,
    ),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.chintunes.chintunes.playback',
      androidNotificationChannelName: 'Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  // Ultra Saver + switching to cellular → drop the prefetched next track.
  network.changes.listen((_) => unawaited(handler.refreshPrefetchPolicy()));

  runApp(ProviderScope(
    overrides: [
      coreServicesProvider.overrideWithValue(core),
      libraryStoreProvider.overrideWithValue(store),
      audioHandlerProvider.overrideWithValue(handler),
      downloadManagerProvider.overrideWithValue(downloads),
      audioCacheProvider.overrideWithValue(cache),
      networkMonitorProvider.overrideWithValue(network),
    ],
    child: const ChinTunesApp(),
  ));
}
