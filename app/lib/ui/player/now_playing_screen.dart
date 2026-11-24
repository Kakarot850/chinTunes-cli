import 'dart:async';

import 'package:chintunes_core/chintunes_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../audio/playback_actions.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';
import '../widgets/artwork.dart';
import '../widgets/seek_bar.dart';
import '../widgets/state_views.dart';
import '../widgets/track_actions.dart';
import 'mini_player.dart';
import 'player_controls.dart';
import 'queue_sheet.dart';
import 'sleep_timer_sheet.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  final DraggableScrollableController _queue = DraggableScrollableController();
  bool _queueOpen = false;

  @override
  void initState() {
    super.initState();
    _queue.addListener(() {
      final open = _queue.isAttached && _queue.size > 0.3;
      if (open != _queueOpen) setState(() => _queueOpen = open);
    });
  }

  @override
  void dispose() {
    _queue.dispose();
    super.dispose();
  }

  void _setQueue({required bool open}) {
    if (!_queue.isAttached) return;
    // Same peek fraction QueuePanel uses (sheet bounds must not be exceeded).
    final peek = ((kQueuePeekHeight + MediaQuery.paddingOf(context).bottom) / MediaQuery.sizeOf(context).height)
        .clamp(0.05, 0.4)
        .toDouble();
    unawaited(_queue.animateTo(
      open ? kQueueMaxSize : peek,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(mediaItemProvider).valueOrNull;
    final handler = ref.read(audioHandlerProvider);
    final track = handler.currentTrack;

    if (item == null || track == null) {
      return Scaffold(
        appBar: AppBar(leading: const _CollapseButton()),
        body: const EmptyView(
          icon: Icons.music_off_rounded,
          title: 'Nothing is playing',
          message: 'Pick a song from Home or Search to start listening.',
        ),
      );
    }

    final artUrl = item.artUri?.toString();
    final scheme = artUrl == null ? null : ref.watch(artColorSchemeProvider(artUrl)).valueOrNull;
    final tint = scheme?.primaryContainer ?? AppColors.accent.withValues(alpha: 0.5);
    final badge = item.extras?['badge'] as String?;
    final sleep = ref.watch(sleepTimerProvider);
    final theme = Theme.of(context);

    return PopScope(
      // Back with the queue open collapses it first.
      canPop: !_queueOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _setQueue(open: false);
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          GestureDetector(
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 300) context.pop();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.lerp(tint, AppColors.background, 0.45)!, AppColors.background],
              stops: const [0, 0.78],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  SizedBox(
                    height: 56,
                    child: Row(
                      children: [
                        const _CollapseButton(),
                        Expanded(
                          child: Text(
                            item.album ?? 'Now playing',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(color: AppColors.textSecondary),
                          ),
                        ),
                        IconButton(
                          tooltip: 'More options',
                          icon: const Icon(Icons.more_vert_rounded),
                          onPressed: () => unawaited(showTrackActions(context, track)),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Swipe the artwork left / right to change songs.
                  GestureDetector(
                    onHorizontalDragEnd: (d) {
                      final v = d.primaryVelocity ?? 0;
                      if (v.abs() < 300) return;
                      unawaited(HapticFeedback.selectionClick());
                      unawaited(v < 0 ? handler.skipToNext() : handler.skipToPrevious());
                    },
                    child: Hero(
                      tag: kNowPlayingArtHero,
                      child: LayoutBuilder(
                        builder: (context, c) {
                          // Cap by height too so small phones never overflow the column.
                          final maxByHeight = MediaQuery.sizeOf(context).height * 0.38;
                          final size = c.maxWidth.clamp(0.0, maxByHeight.clamp(160.0, 420.0)).toDouble();
                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: Artwork(key: ValueKey(item.id), url: artUrl, size: size, radius: 16),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.artist ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      LikeButton(track: track, size: 28),
                    ],
                  ),
                  const SizedBox(height: 16),
                  RepaintBoundary(child: PlayerSeekBar(duration: item.duration)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const ShuffleButton(),
                      IconButton(
                        tooltip: 'Previous track',
                        iconSize: 36,
                        color: AppColors.textPrimary,
                        icon: const Icon(Icons.skip_previous_rounded),
                        onPressed: () => unawaited(handler.skipToPrevious()),
                      ),
                      const PlayPauseButton(size: 72, filled: true),
                      IconButton(
                        tooltip: 'Next track',
                        iconSize: 36,
                        color: AppColors.textPrimary,
                        icon: const Icon(Icons.skip_next_rounded),
                        onPressed: () => unawaited(handler.skipToNext()),
                      ),
                      const RepeatButton(),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Sleep timer',
                        color: sleep.isActive ? AppColors.accent : AppColors.textSecondary,
                        icon: const Icon(Icons.bedtime_outlined),
                        onPressed: () => unawaited(showSleepTimerSheet(context)),
                      ),
                      IconButton(
                        tooltip: 'Start mix from this song',
                        color: handler.mixTitle != null ? AppColors.accent : AppColors.textSecondary,
                        icon: const Icon(Icons.radio_rounded),
                        onPressed: () => unawaited(ref.startMix(context, track)),
                      ),
                      Expanded(
                        child: Center(child: badge == null ? const SizedBox.shrink() : _SourceBadge(label: badge)),
                      ),
                      _DownloadButton(track: track),
                      IconButton(
                        tooltip: 'Queue',
                        color: AppColors.textSecondary,
                        icon: const Icon(Icons.format_list_bulleted_rounded),
                        onPressed: () => _setQueue(open: true),
                      ),
                    ],
                  ),
                  // Keep the controls above the collapsed "Up next" strip.
                  const SizedBox(height: kQueuePeekHeight + 8),
                ],
              ),
            ),
          ),
        ),
      ),
          // Drag up from the bottom to reveal the queue.
          QueuePanel(controller: _queue),
        ],
      ),
      ),
    );
  }
}

class _DownloadButton extends ConsumerWidget {
  const _DownloadButton({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(downloadTaskProvider(track.uid));
    if (task == null) {
      return IconButton(
        tooltip: 'Download',
        color: AppColors.textSecondary,
        icon: const Icon(Icons.download_rounded),
        onPressed: () => ref.download(context, track),
      );
    }
    if (task.isCompleted) {
      return const IconButton(
        tooltip: 'Downloaded',
        color: AppColors.success,
        icon: Icon(Icons.download_done_rounded),
        onPressed: null,
      );
    }
    return SizedBox.square(
      dimension: 48,
      child: Center(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2.5, value: task.progress),
        ),
      ),
    );
  }
}

class _CollapseButton extends StatelessWidget {
  const _CollapseButton();

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Minimize player',
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
        onPressed: () => context.pop(),
      );
}

/// Source + bitrate, e.g. "JioSaavn · 320 kbps AAC".
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 0.2,
                ),
          ),
        ),
      );
}
