import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';
import '../widgets/artwork.dart';

/// Height of the collapsed "Up next" strip (excluding the system inset).
const double kQueuePeekHeight = 64;
const double kQueueMaxSize = 0.92;

/// Pull-up queue on Now Playing: a peek strip at the bottom that can be
/// dragged (or tapped) up into a full, reorderable queue. Drag the handle to
/// reorder, swipe left to remove, tap to jump.
class QueuePanel extends ConsumerWidget {
  const QueuePanel({super.key, required this.controller});

  final DraggableScrollableController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        final peek = ((kQueuePeekHeight + bottomInset) / constraints.maxHeight).clamp(0.05, 0.4).toDouble();
        return DraggableScrollableSheet(
          controller: controller,
          initialChildSize: peek,
          minChildSize: peek,
          maxChildSize: kQueueMaxSize,
          snap: true,
          builder: (context, scrollController) => Material(
            color: AppColors.elevated,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              side: BorderSide(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: _QueueList(
              scrollController: scrollController,
              bottomInset: bottomInset,
              onHeaderTap: () {
                if (!controller.isAttached) return;
                final expanded = controller.size > peek + 0.05;
                unawaited(controller.animateTo(
                  expanded ? peek : kQueueMaxSize,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                ));
              },
            ),
          ),
        );
      },
    );
  }
}

class _QueueList extends ConsumerWidget {
  const _QueueList({required this.scrollController, required this.bottomInset, required this.onHeaderTap});

  final ScrollController scrollController;
  final double bottomInset;
  final VoidCallback onHeaderTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(queueProvider).valueOrNull ?? const [];
    final current = ref.watch(playbackStateProvider.select((s) => s.valueOrNull?.queueIndex));
    final handler = ref.read(audioHandlerProvider);
    final theme = Theme.of(context);
    final nextIndex = current == null ? null : current + 1;
    final upNext = (nextIndex != null && nextIndex < items.length) ? items[nextIndex] : null;
    final remaining = current == null ? items.length : math.max(0, items.length - current - 1);
    final mixTitle = handler.mixTitle;

    final header = GestureDetector(
      key: const ValueKey('queue-header'),
      behavior: HitTestBehavior.opaque,
      onTap: onHeaderTap,
      child: SizedBox(
        height: kQueuePeekHeight,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: AppColors.textTertiary, borderRadius: BorderRadius.circular(2)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.queue_music_rounded, size: 20, color: AppColors.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Up next · $remaining', style: theme.textTheme.titleSmall),
                          Text(
                            mixTitle ?? (upNext == null ? 'End of queue' : '${upNext.title} · ${upNext.artist ?? ''}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: mixTitle != null ? AppColors.accent : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_up_rounded, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return ReorderableListView.builder(
      scrollController: scrollController,
      header: header,
      buildDefaultDragHandles: false,
      // Room for the gesture bar so the last song is fully reachable (B-039).
      padding: EdgeInsets.only(bottom: bottomInset + 24),
      itemCount: items.length,
      // onReorderItem (Flutter ≥ 3.41) already adjusts newIndex for the removed item.
      onReorderItem: (oldIndex, newIndex) => unawaited(handler.moveQueueItem(oldIndex, newIndex)),
      itemBuilder: (context, i) {
        final item = items[i];
        final isCurrent = i == current;
        return Dismissible(
          key: ValueKey('${item.id}#$i'),
          direction: isCurrent ? DismissDirection.none : DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: AppColors.danger.withValues(alpha: 0.18),
            child: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
          ),
          onDismissed: (_) => unawaited(handler.removeQueueItemAt(i)),
          child: ListTile(
            onTap: () => unawaited(handler.skipToQueueItem(i)),
            leading: Artwork(url: item.artUri?.toString(), size: 44, radius: 6),
            title: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isCurrent ? AppColors.accent : AppColors.textPrimary,
                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            subtitle: Text(item.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: ReorderableDragStartListener(
              index: i,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.drag_handle_rounded, semanticLabel: 'Reorder'),
              ),
            ),
          ),
        );
      },
    );
  }
}
