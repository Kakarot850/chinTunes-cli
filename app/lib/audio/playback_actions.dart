import 'dart:async';
import 'dart:math';

import 'package:chintunes_core/chintunes_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';

/// Thin helpers so widgets don't talk to the handler directly.
extension PlaybackActions on WidgetRef {
  void playQueue(List<Track> tracks, {int index = 0}) {
    unawaited(read(audioHandlerProvider).playTracks(tracks, startIndex: index, shuffle: false));
  }

  void shufflePlay(List<Track> tracks) {
    if (tracks.isEmpty) return;
    final start = Random().nextInt(tracks.length);
    unawaited(read(audioHandlerProvider).playTracks(tracks, startIndex: start, shuffle: true));
  }

  /// Opens a single browse card of type `song` (launch data items lack media urls).
  Future<void> playSummary(BuildContext context, CollectionSummary summary) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final col = await read(coreServicesProvider).catalog.open(summary);
      playQueue(col.tracks);
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Couldn\'t load "${summary.title}". Check your connection and try again.')),
      );
    }
  }

  /// "Start Mix": endless YouTube Music radio seeded from [seed]. The seed
  /// itself plays first (from its own source, e.g. JioSaavn 320 kbps).
  Future<void> startMix(BuildContext context, Track seed) async {
    // Read everything before the first await: callers (e.g. a bottom sheet)
    // may be disposed while the mix loads.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final mixes = read(coreServicesProvider).mixes;
    final handler = read(audioHandlerProvider);
    messenger?.showSnackBar(SnackBar(
      content: Text('Starting a mix from "${seed.title}"…'),
      duration: const Duration(seconds: 2),
    ));
    try {
      final session = await mixes.start(seed);
      await handler.startMix(session, lead: seed);
    } catch (e) {
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(
        content: Text(e is MixException ? e.message : 'Couldn\'t start a mix. Check your connection and try again.'),
      ));
    }
  }

  /// Queues an offline download in the current Data Mode.
  void download(BuildContext context, Track track) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    unawaited(read(downloadManagerProvider).enqueue(track));
    messenger?.showSnackBar(SnackBar(
      content: Text('Downloading "${track.title}"'),
      duration: const Duration(seconds: 2),
    ));
  }
}
