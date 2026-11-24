import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../data/providers.dart';

/// Pure, testable seek bar: renders [position]/[duration] and reports seeks.
class SeekBarView extends StatefulWidget {
  const SeekBarView({super.key, required this.position, required this.duration, required this.onSeek});

  final Duration position;
  final Duration? duration;
  final ValueChanged<Duration> onSeek;

  @override
  State<SeekBarView> createState() => _SeekBarViewState();
}

class _SeekBarViewState extends State<SeekBarView> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final totalMs = math.max(widget.duration?.inMilliseconds ?? 0, 1).toDouble();
    final double valueMs = (_dragMs ?? widget.position.inMilliseconds.toDouble()).clamp(0.0, totalMs).toDouble();
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 32,
          child: Slider(
            value: valueMs,
            max: totalMs,
            onChanged: widget.duration == null ? null : (v) => setState(() => _dragMs = v),
            onChangeEnd: widget.duration == null
                ? null
                : (v) {
                    widget.onSeek(Duration(milliseconds: v.round()));
                    setState(() => _dragMs = null);
                  },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatDuration(Duration(milliseconds: valueMs.round())), style: style),
              Text(formatDuration(widget.duration), style: style),
            ],
          ),
        ),
      ],
    );
  }
}

/// Seek bar bound to the player. Only this subtree rebuilds on 200 ms ticks.
class PlayerSeekBar extends ConsumerWidget {
  const PlayerSeekBar({super.key, required this.duration});

  final Duration? duration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.read(audioHandlerProvider);
    return StreamBuilder<Duration>(
      stream: ref.watch(positionStreamProvider),
      builder: (context, snapshot) => SeekBarView(
        position: snapshot.data ?? Duration.zero,
        duration: duration,
        onSeek: (d) => unawaited(handler.seek(d)),
      ),
    );
  }
}

/// 2px progress line for the mini-player.
class MiniProgressLine extends ConsumerWidget {
  const MiniProgressLine({super.key, required this.duration});

  final Duration? duration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<Duration>(
      stream: ref.watch(positionStreamProvider),
      builder: (context, snapshot) {
        final total = duration?.inMilliseconds ?? 0;
        final pos = snapshot.data?.inMilliseconds ?? 0;
        final double value = total <= 0 ? 0.0 : (pos / total).clamp(0.0, 1.0).toDouble();
        return LinearProgressIndicator(value: value, minHeight: 2, color: AppColors.textPrimary);
      },
    );
  }
}
