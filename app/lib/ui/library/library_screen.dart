import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../data/library_store.dart';
import '../../data/providers.dart';
import '../widgets/artwork.dart';
import '../widgets/state_views.dart';
import '../widgets/track_actions.dart';

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, color: color),
      );
}

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final store = ref.read(libraryStoreProvider);
    final name = await promptPlaylistName(context, title: 'New playlist', confirmLabel: 'Create playlist');
    if (name != null) await store.createPlaylist(name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(likedTracksProvider).valueOrNull ?? const [];
    final playlists = ref.watch(playlistsProvider).valueOrNull ?? const <LocalPlaylist>[];
    final downloaded = ref.watch(downloadedIdsProvider).length;
    final activeDownloads = (ref.watch(downloadsProvider).valueOrNull ?? const []).where((t) => t.isActive).length;
    final storage = ref.watch(storageUsageProvider).valueOrNull;
    final signedIn = ref.watch(accountProvider.select((s) => s.signedIn));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Your Library', style: theme.textTheme.titleLarge),
        actions: [
          IconButton(
            tooltip: 'Create playlist',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => unawaited(_create(context, ref)),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => unawaited(context.push('/settings')),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24),
        children: [
          ListTile(
            onTap: () => context.go('/library/liked'),
            leading: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: LinearGradient(
                  colors: [AppColors.accent, AppColors.accent.withValues(alpha: 0.35)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(Icons.favorite_rounded, color: AppColors.textPrimary),
            ),
            title: const Text('Liked Songs'),
            subtitle: Text(pluralize(liked.length, 'song')),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
          ListTile(
            onTap: () => context.go('/library/downloads'),
            leading: const _IconBox(icon: Icons.download_for_offline_rounded, color: AppColors.success),
            title: const Text('Downloads'),
            subtitle: Text(
              [
                pluralize(downloaded, 'song'),
                if (activeDownloads > 0) '$activeDownloads in progress',
                if (storage != null && storage.downloads > 0) formatBytes(storage.downloads),
              ].join(' · '),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
          ListTile(
            onTap: () => context.go('/library/youtube'),
            leading: const _IconBox(icon: Icons.smart_display_rounded, color: AppColors.danger),
            title: const Text('YouTube & History'),
            subtitle: Text(signedIn ? 'Liked music, playlists and play history' : 'Play history · sign in for YouTube likes'),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
          SectionHeader(
            'Playlists',
            trailing: TextButton.icon(
              onPressed: () => unawaited(_create(context, ref)),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New playlist'),
            ),
          ),
          if (playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('Create a playlist, then add songs from any track\'s menu.'),
            ),
          for (final p in playlists)
            ListTile(
              onTap: () => context.go('/library/playlist/${p.id}'),
              leading: p.tracks.isEmpty
                  ? Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.elevated,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.queue_music_rounded, color: AppColors.textTertiary),
                    )
                  : Artwork(url: p.tracks.first.imageUrl, size: 52, radius: 6),
              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(pluralize(p.tracks.length, 'song')),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
        ],
      ),
    );
  }
}
