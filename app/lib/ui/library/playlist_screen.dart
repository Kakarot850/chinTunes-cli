import 'dart:async';

import 'package:chintunes_core/chintunes_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../data/library_store.dart';
import '../../data/providers.dart';
import '../widgets/state_views.dart';
import '../widgets/track_actions.dart';
import 'import_playlist_sheet.dart';
import 'liked_screen.dart';

enum _PlaylistMenu { rename, delete, stopSync }

class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({super.key, required this.playlistId});

  final String playlistId;

  Future<void> _rename(BuildContext context, LibraryStore store, LocalPlaylist p) async {
    final name = await promptPlaylistName(context, title: 'Rename playlist', confirmLabel: 'Save name', initial: p.name);
    if (name != null) await store.renamePlaylist(p.id, name);
  }

  Future<void> _delete(BuildContext context, LibraryStore store, LocalPlaylist p) async {
    final router = GoRouter.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${p.name}"?'),
        content: const Text('The playlist will be removed. Songs stay in your other playlists and Liked Songs.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Delete "${p.name}"'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await store.deletePlaylist(p.id);
    router.go('/library');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(libraryStoreProvider);
    final playlists = ref.watch(playlistsProvider).valueOrNull;
    if (playlists == null) return const Scaffold(body: LoadingView());

    final matches = playlists.where((p) => p.id == playlistId);
    if (matches.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyView(icon: Icons.playlist_remove_rounded, title: 'This playlist no longer exists'),
      );
    }
    final p = matches.first;
    final sync = ref.read(playlistSyncProvider);

    final list = p.tracks.isEmpty
        ? EmptyView(
            icon: Icons.queue_music_rounded,
            title: 'This playlist is empty',
            message: p.isSynced ? 'Songs added in ${p.sync!.ref.service.label} appear after the next sync.' : 'Use "Add to playlist" from any song\'s menu.',
          )
        : TrackListBody(
            tracks: p.tracks,
            header: pluralize(p.tracks.length, 'song'),
            // Synced playlists mirror the remote: a local removal would come back.
            onRemove: p.isSynced ? null : (index) => unawaited(store.removeFromPlaylist(p.id, index)),
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          if (p.isSynced)
            ValueListenableBuilder<Set<String>>(
              valueListenable: sync.syncing,
              builder: (context, busy, _) => busy.contains(p.id)
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton(
                      tooltip: 'Sync now',
                      icon: const Icon(Icons.sync_rounded),
                      onPressed: () => unawaited(_sync(context, ref, p)),
                    ),
            ),
          PopupMenuButton<_PlaylistMenu>(
            tooltip: 'Playlist options',
            onSelected: (choice) => unawaited(switch (choice) {
              _PlaylistMenu.rename => _rename(context, store, p),
              _PlaylistMenu.delete => _delete(context, store, p),
              _PlaylistMenu.stopSync => store.stopSyncing(p.id),
            }),
            itemBuilder: (context) => [
              const PopupMenuItem(value: _PlaylistMenu.rename, child: Text('Rename playlist')),
              if (p.isSynced) const PopupMenuItem(value: _PlaylistMenu.stopSync, child: Text('Stop syncing')),
              const PopupMenuItem(value: _PlaylistMenu.delete, child: Text('Delete playlist')),
            ],
          ),
        ],
      ),
      body: p.isSynced ? Column(children: [_SyncStatus(playlist: p), Expanded(child: list)]) : list,
    );
  }

  Future<void> _sync(BuildContext context, WidgetRef ref, LocalPlaylist p) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final diff = await ref.read(playlistSyncProvider).sync(p.id);
      messenger.showSnackBar(SnackBar(content: Text('${p.name}: ${diff.summary}')));
    } on ImportException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _SyncStatus extends StatelessWidget {
  const _SyncStatus({required this.playlist});

  final LocalPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    final info = playlist.sync!;
    final theme = Theme.of(context);
    final when = info.lastSyncedAt == null ? 'not synced yet' : 'updated ${formatRelative(info.lastSyncedAt!)}';
    final error = info.lastError;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: error == null ? AppColors.border : AppColors.danger.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(serviceIcon(info.ref.service), size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Synced from ${info.ref.service.label} · $when', style: theme.textTheme.bodyMedium),
                Text(
                  error ??
                      [
                        if (info.lastSummary != null) info.lastSummary!,
                        if (info.truncated) 'first ~100 songs only',
                        'checks for new songs whenever you open the app',
                      ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: error == null ? null : AppColors.danger),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
