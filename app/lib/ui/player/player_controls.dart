import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:chintunes_core/chintunes_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';

/// Play/pause that shows a spinner while resolving/buffering.
class PlayPauseButton extends ConsumerWidget {
  const PlayPauseButton({super.key, this.size = 40, this.filled = false});

  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(isPlayingProvider);
    final buffering = ref.watch(isBufferingProvider);
    final handler = ref.read(audioHandlerProvider);
    final fg = filled ? AppColors.background : AppColors.textPrimary;

    final Widget icon = buffering
        ? SizedBox.square(
            dimension: size * 0.42,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
          )
        : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: size * 0.6, color: fg);

    return SizedBox.square(
      dimension: size,
      child: Material(
        color: filled ? AppColors.textPrimary : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => unawaited(playing ? handler.pause() : handler.play()),
          child: Semantics(
            button: true,
            label: playing ? 'Pause' : 'Play',
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}

class ShuffleButton extends ConsumerWidget {
  const ShuffleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(playbackStateProvider.select(
      (s) => (s.valueOrNull?.shuffleMode ?? AudioServiceShuffleMode.none) != AudioServiceShuffleMode.none,
    ));
    return IconButton(
      tooltip: on ? 'Turn shuffle off' : 'Turn shuffle on',
      isSelected: on,
      color: on ? AppColors.accent : AppColors.textSecondary,
      icon: const Icon(Icons.shuffle_rounded),
      onPressed: () => unawaited(ref.read(audioHandlerProvider).setShuffleMode(
            on ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all,
          )),
    );
  }
}

class RepeatButton extends ConsumerWidget {
  const RepeatButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(playbackStateProvider.select(
      (s) => s.valueOrNull?.repeatMode ?? AudioServiceRepeatMode.none,
    ));
    final (next, icon, tooltip) = switch (mode) {
      AudioServiceRepeatMode.none => (AudioServiceRepeatMode.all, Icons.repeat_rounded, 'Repeat all'),
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group =>
        (AudioServiceRepeatMode.one, Icons.repeat_rounded, 'Repeat one'),
      AudioServiceRepeatMode.one => (AudioServiceRepeatMode.none, Icons.repeat_one_rounded, 'Turn repeat off'),
    };
    final active = mode != AudioServiceRepeatMode.none;
    return IconButton(
      tooltip: tooltip,
      color: active ? AppColors.accent : AppColors.textSecondary,
      icon: Icon(icon),
      onPressed: () => unawaited(ref.read(audioHandlerProvider).setRepeatMode(next)),
    );
  }
}

class LikeButton extends ConsumerWidget {
  const LikeButton({super.key, required this.track, this.size = 24});

  final Track track;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(likedIdsProvider).contains(track.uid);
    return IconButton(
      tooltip: liked ? 'Remove from Liked Songs' : 'Add to Liked Songs',
      iconSize: size,
      color: liked ? AppColors.accent : AppColors.textSecondary,
      icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded),
      onPressed: () => unawaited(ref.read(libraryStoreProvider).setLiked(track, !liked)),
    );
  }
}
