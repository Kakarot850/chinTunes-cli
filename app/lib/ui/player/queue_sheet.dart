import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';
import '../widgets/artwork.dart';

Future<void> showQueueSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const QueueSheet(),
    );

/// Reorderable queue: drag the handle to reorder, swipe to remove, tap to jump.
class QueueSheet extends ConsumerWidget {
  const QueueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(queueProvider).valueOrNull ?? const [];
    final current = ref.watch(playbackStateProvider.select((s) => s.valueOrNull?.queueIndex));
    final handler = ref.read(audioHandlerProvider);
    final theme = Theme.of(context);

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.72,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Up next', style: theme.textTheme.titleLarge),
                if (handler.mixTitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.radio_rounded, size: 14, color: AppColors.accent),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Endless mix · ${handler.mixTitle}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.accent),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
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
            ),
          ),
        ],
      ),
    );
  }
}
