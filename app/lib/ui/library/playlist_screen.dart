import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../data/library_store.dart';
import '../../data/providers.dart';
import '../widgets/state_views.dart';
import '../widgets/track_actions.dart';
import 'liked_screen.dart';

enum _PlaylistMenu { rename, delete }

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

    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          PopupMenuButton<_PlaylistMenu>(
            tooltip: 'Playlist options',
            onSelected: (choice) => unawaited(switch (choice) {
              _PlaylistMenu.rename => _rename(context, store, p),
              _PlaylistMenu.delete => _delete(context, store, p),
            }),
            itemBuilder: (context) => const [
              PopupMenuItem(value: _PlaylistMenu.rename, child: Text('Rename playlist')),
              PopupMenuItem(value: _PlaylistMenu.delete, child: Text('Delete playlist')),
            ],
          ),
        ],
      ),
      body: p.tracks.isEmpty
          ? const EmptyView(
              icon: Icons.queue_music_rounded,
              title: 'This playlist is empty',
              message: 'Use "Add to playlist" from any song\'s menu.',
            )
          : TrackListBody(
              tracks: p.tracks,
              header: pluralize(p.tracks.length, 'song'),
              onRemove: (index) => unawaited(store.removeFromPlaylist(p.id, index)),
            ),
    );
  }
}
