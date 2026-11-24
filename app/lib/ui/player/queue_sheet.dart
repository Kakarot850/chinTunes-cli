import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';
import '../widgets/artwork.dart';

/// Height of the collapsed "Up next" strip (excluding the system inset).
const double kQueuePeekHeight = 68;
const double kQueueHalfSize = 0.55;
const double kQueueMaxSize = 0.92;
const double _kRowExtent = 72;

double queuePeekFraction(BuildContext context, double maxHeight) =>
    ((kQueuePeekHeight + MediaQuery.paddingOf(context).bottom) / maxHeight).clamp(0.05, 0.4).toDouble();

/// Pull-up queue on Now Playing (B-039, B-041).
///
/// Snaps to peek / half / full. The peek strip shows the next song; the
/// chevron follows the drag. Opening scrolls to the playing song; played
/// songs are dimmed. Drag the handle to reorder, swipe left to remove, tap
/// to jump. Expanded header: shuffle + "Clear upcoming".
class QueuePanel extends ConsumerStatefulWidget {
  const QueuePanel({super.key, required this.controller});

  final DraggableScrollableController controller;

  @override
  ConsumerState<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends ConsumerState<QueuePanel> {
  /// 0 = collapsed, 1 = fully expanded (drives chevron + header actions only,
  /// so drags don't rebuild the list).
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  ScrollController? _list;
  bool _wasOpen = false;

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _toggle(double peek) {
    final c = widget.controller;
    if (!c.isAttached) return;
    final open = c.size > peek + 0.05;
    unawaited(HapticFeedback.selectionClick());
    unawaited(c.animateTo(
      open ? peek : kQueueMaxSize,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    ));
  }

  /// When the panel opens, bring the playing song near the top.
  void _scrollToCurrent() {
    final list = _list;
    final current = ref.read(playbackStateProvider).valueOrNull?.queueIndex;
    if (list == null || !list.hasClients || current == null) return;
    final target = math.max(0.0, (current - 1) * _kRowExtent).toDouble();
    unawaited(list.animateTo(
      math.min(target, list.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final peek = queuePeekFraction(context, constraints.maxHeight);
        return NotificationListener<DraggableScrollableNotification>(
          onNotification: (n) {
            _progress.value = ((n.extent - peek) / (kQueueMaxSize - peek)).clamp(0.0, 1.0).toDouble();
            final open = n.extent >= kQueueHalfSize - 0.02;
            if (open && !_wasOpen) _scrollToCurrent();
            _wasOpen = open;
            return false;
          },
          child: DraggableScrollableSheet(
            controller: widget.controller,
            initialChildSize: peek,
            minChildSize: peek,
            maxChildSize: kQueueMaxSize,
            snap: true,
            snapSizes: [if (kQueueHalfSize > peek + 0.05) kQueueHalfSize],
            builder: (context, scrollController) {
              _list = scrollController;
              return Material(
                color: AppColors.elevated,
                elevation: 12,
                shadowColor: Colors.black,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                  side: BorderSide(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: _QueueList(
                  scrollController: scrollController,
                  progress: _progress,
                  onHeaderTap: () => _toggle(peek),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _QueueList extends ConsumerWidget {
  const _QueueList({required this.scrollController, required this.progress, required this.onHeaderTap});

  final ScrollController scrollController;
  final ValueNotifier<double> progress;
  final VoidCallback onHeaderTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(queueProvider).valueOrNull ?? const <MediaItem>[];
    final current = ref.watch(playbackStateProvider.select((s) => s.valueOrNull?.queueIndex));
    final handler = ref.read(audioHandlerProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return ReorderableListView.builder(
      scrollController: scrollController,
      header: _QueueHeader(
        items: items,
        current: current,
        mixTitle: handler.mixTitle,
        progress: progress,
        onTap: onHeaderTap,
      ),
      buildDefaultDragHandles: false,
      itemExtent: _kRowExtent,
      // Room for the gesture bar so the last song is fully reachable (B-039).
      padding: EdgeInsets.only(bottom: bottomInset + 24),
      itemCount: items.length,
      // onReorderItem (Flutter ≥ 3.41) already adjusts newIndex for the removed item.
      onReorderItem: (oldIndex, newIndex) => unawaited(handler.moveQueueItem(oldIndex, newIndex)),
      itemBuilder: (context, i) {
        final item = items[i];
        final isCurrent = i == current;
        final played = current != null && i < current;
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
          child: Opacity(
            opacity: played ? 0.45 : 1,
            child: ListTile(
              onTap: () => unawaited(handler.skipToQueueItem(i)),
              tileColor: isCurrent ? AppColors.accent.withValues(alpha: 0.10) : null,
              leading: Stack(
                alignment: Alignment.center,
                children: [
                  Artwork(url: item.artUri?.toString(), size: 44, radius: 6),
                  if (isCurrent)
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.graphic_eq_rounded, color: AppColors.accent, size: 22),
                    ),
                ],
              ),
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
          ),
        );
      },
    );
  }
}

class _QueueHeader extends ConsumerWidget {
  const _QueueHeader({
    required this.items,
    required this.current,
    required this.mixTitle,
    required this.progress,
    required this.onTap,
  });

  final List<MediaItem> items;
  final int? current;
  final String? mixTitle;
  final ValueNotifier<double> progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final handler = ref.read(audioHandlerProvider);
    final cur = current;
    final nextIndex = cur == null ? null : cur + 1;
    final upNext = (nextIndex != null && nextIndex < items.length) ? items[nextIndex] : null;
    final remaining = cur == null ? items.length : math.max(0, items.length - cur - 1);
    final shuffleOn = ref.watch(playbackStateProvider.select(
      (s) => (s.valueOrNull?.shuffleMode ?? AudioServiceShuffleMode.none) != AudioServiceShuffleMode.none,
    ));

    return GestureDetector(
      key: const ValueKey('queue-header'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
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
                    padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
                    child: Row(
                      children: [
                        Artwork(url: upNext?.artUri?.toString(), size: 36, radius: 6),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                upNext == null ? 'Up next' : 'Up next · ${pluralizeSongs(remaining)}',
                                style: theme.textTheme.titleSmall,
                              ),
                              Text(
                                upNext == null
                                    ? (mixTitle ?? 'End of queue')
                                    : '${upNext.title}${(upNext.artist ?? '').isEmpty ? '' : ' · ${upNext.artist}'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        ValueListenableBuilder<double>(
                          valueListenable: progress,
                          builder: (context, p, _) => Transform.rotate(
                            angle: math.pi * p,
                            child: const Icon(Icons.keyboard_arrow_up_rounded, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Expanded-only actions fade in as the panel opens.
          ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (context, p, child) => p < 0.15
                ? const SizedBox.shrink()
                : Opacity(opacity: ((p - 0.15) / 0.35).clamp(0.0, 1.0).toDouble(), child: child),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  if (mixTitle != null)
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.all_inclusive_rounded, size: 16, color: AppColors.accent),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              mixTitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.accent),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const Spacer(),
                  FilterChip(
                    avatar: const Icon(Icons.shuffle_rounded, size: 16),
                    label: const Text('Shuffle'),
                    selected: shuffleOn,
                    onSelected: (on) => unawaited(handler.setShuffleMode(
                      on ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
                    )),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: remaining == 0 ? null : () => unawaited(handler.clearUpcoming()),
                    icon: const Icon(Icons.clear_all_rounded, size: 18),
                    label: const Text('Clear upcoming'),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

String pluralizeSongs(int n) => n == 1 ? '1 song' : '$n songs';
