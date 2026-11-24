import 'dart:async';

import 'package:chintunes_core/chintunes_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/playback_actions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../data/providers.dart';
import '../widgets/artwork.dart';
import '../widgets/state_views.dart';

/// Library → Downloads: progress, pause / resume / cancel / delete, storage.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(downloadsProvider).valueOrNull ?? const <DownloadTask>[];
    final usage = ref.watch(storageUsageProvider).valueOrNull;
    final manager = ref.read(downloadManagerProvider);
    final completed = tasks.where((t) => t.isCompleted).toList();
    final playable = completed.map((t) => manager.localize(t.track)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: tasks.isEmpty
          ? const EmptyView(
              icon: Icons.download_for_offline_outlined,
              title: 'No downloads yet',
              message: 'Open any song\'s menu and choose Download to listen without a connection.',
            )
          : ListView.builder(
              padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24),
              itemCount: tasks.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            [
                              pluralize(completed.length, 'song'),
                              if (usage != null) '${formatBytes(usage.downloads)} on this device',
                            ].join(' · '),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        if (playable.isNotEmpty)
                          FilledButton.icon(
                            onPressed: () => ref.playQueue(playable),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Play'),
                          ),
                      ],
                    ),
                  );
                }
                final task = tasks[i - 1];
                return _DownloadTile(
                  task: task,
                  onPlay: task.isCompleted
                      ? () => ref.playQueue(playable, index: playable.indexWhere((t) => t.uid == task.uid))
                      : null,
                );
              },
            ),
    );
  }
}

class _DownloadTile extends ConsumerWidget {
  const _DownloadTile({required this.task, this.onPlay});

  final DownloadTask task;
  final VoidCallback? onPlay;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final manager = ref.read(downloadManagerProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove "${task.track.title}"?'),
        content: const Text('The downloaded file is deleted from this device. You can download it again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove download'),
          ),
        ],
      ),
    );
    if (ok == true) await manager.delete(task.uid);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.read(downloadManagerProvider);
    final theme = Theme.of(context);
    final cover = manager.localize(task.track).imageUrl;
    final received = formatBytes(task.receivedBytes);
    final total = task.totalBytes == null ? null : formatBytes(task.totalBytes!);

    final Widget subtitle = switch (task.status) {
      DownloadStatus.completed => Row(
          children: [
            const Icon(Icons.download_done_rounded, size: 14, color: AppColors.success),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                [
                  task.track.artist,
                  if (total != null) total,
                  if (task.bitrateKbps != null) '${task.bitrateKbps} kbps',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      DownloadStatus.downloading || DownloadStatus.queued || DownloadStatus.paused => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: task.status == DownloadStatus.queued ? null : task.progress,
              minHeight: 3,
              color: task.status == DownloadStatus.paused ? AppColors.textTertiary : AppColors.accent,
            ),
            const SizedBox(height: 4),
            Text(
              switch (task.status) {
                DownloadStatus.queued => 'Waiting to download',
                DownloadStatus.paused => 'Paused · $received${total == null ? '' : ' of $total'}',
                _ => '$received${total == null ? '' : ' of $total'}',
              },
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      DownloadStatus.failed => Text(
          task.error ?? 'Download failed.',
          maxLines: 2,
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.danger),
        ),
    };

    final Widget action = switch (task.status) {
      DownloadStatus.downloading || DownloadStatus.queued => IconButton(
          tooltip: 'Pause download',
          icon: const Icon(Icons.pause_rounded),
          onPressed: () => unawaited(manager.pause(task.uid)),
        ),
      DownloadStatus.paused || DownloadStatus.failed => IconButton(
          tooltip: task.status == DownloadStatus.failed ? 'Retry download' : 'Resume download',
          icon: Icon(task.status == DownloadStatus.failed ? Icons.refresh_rounded : Icons.play_arrow_rounded),
          onPressed: () => unawaited(manager.resume(task.uid)),
        ),
      DownloadStatus.completed => IconButton(
          tooltip: 'Remove download',
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: () => unawaited(_confirmDelete(context, ref)),
        ),
    };

    return ListTile(
      onTap: onPlay,
      onLongPress: task.isCompleted ? null : () => unawaited(manager.cancel(task.uid)),
      leading: Artwork(url: cover, size: 48, radius: 6),
      title: Text(task.track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          action,
          if (!task.isCompleted)
            IconButton(
              tooltip: 'Cancel download',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => unawaited(manager.cancel(task.uid)),
            ),
        ],
      ),
    );
  }
}
