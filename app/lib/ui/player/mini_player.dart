import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';
import '../widgets/artwork.dart';
import '../widgets/seek_bar.dart';
import '../widgets/track_actions.dart';
import 'player_controls.dart';

const String kNowPlayingArtHero = 'now-playing-art';

/// Docked above the navigation bar.
/// - tap / swipe up → Now Playing
/// - swipe left / right → next / previous song
/// - long-press → like, add to playlist, download, start mix…
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(mediaItemProvider).valueOrNull;
    if (item == null) return const SizedBox.shrink();
    final handler = ref.read(audioHandlerProvider);
    final track = handler.currentTrack;
    final theme = Theme.of(context);

    void open() => unawaited(context.push('/player'));

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: open,
          onLongPress: track == null ? null : () => unawaited(showTrackActions(context, track)),
          child: GestureDetector(
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < -250) open();
            },
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v.abs() < 300) return;
              unawaited(HapticFeedback.selectionClick());
              unawaited(v < 0 ? handler.skipToNext() : handler.skipToPrevious());
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 60,
                  child: Row(
                    children: [
                      const SizedBox(width: 10),
                      Hero(
                        tag: kNowPlayingArtHero,
                        child: Artwork(url: item.artUri?.toString(), size: 42, radius: 8),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Column(
                            key: ValueKey(item.id),
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.artist ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (track != null) LikeButton(track: track, size: 22),
                      const PlayPauseButton(size: 44),
                      IconButton(
                        tooltip: 'Next track',
                        icon: const Icon(Icons.skip_next_rounded),
                        color: AppColors.textPrimary,
                        onPressed: () => unawaited(handler.skipToNext()),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
                // Repaints every 200 ms; keep it on its own layer.
                RepaintBoundary(child: MiniProgressLine(duration: item.duration)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
