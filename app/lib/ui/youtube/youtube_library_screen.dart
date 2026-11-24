import 'dart:async';

import 'package:chintunes_core/chintunes_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../audio/playback_actions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../data/google_account.dart';
import '../../data/providers.dart';
import '../library/liked_screen.dart';
import '../widgets/artwork.dart';
import '../widgets/collection_card.dart';
import '../widgets/state_views.dart';
import 'takeout_import.dart';

/// Library → YouTube & History: liked music/videos, playlists (signed in)
/// and local + Google Takeout history (works in guest mode too).
class YouTubeLibraryScreen extends ConsumerWidget {
  const YouTubeLibraryScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider);
    final musicOnly = ref.watch(musicOnlyProvider);
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('YouTube & History'),
          actions: [
            IconButton(
              tooltip: musicOnly ? 'Show music and videos' : 'Show music only',
              isSelected: musicOnly,
              color: musicOnly ? AppColors.accent : AppColors.textSecondary,
              icon: const Icon(Icons.music_note_rounded),
              onPressed: () => unawaited(ref.read(musicOnlyProvider.notifier).set(!musicOnly)),
            ),
            if (account.signedIn)
              PopupMenuButton<String>(
                tooltip: 'Account',
                icon: CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.elevated,
                  backgroundImage: account.user!.photoUrl == null ? null : NetworkImage(account.user!.photoUrl!),
                  child: account.user!.photoUrl == null ? const Icon(Icons.person_rounded, size: 16) : null,
                ),
                onSelected: (_) => unawaited(ref.read(accountProvider.notifier).signOut()),
                itemBuilder: (context) => [
                  PopupMenuItem(enabled: false, child: Text(account.user!.email)),
                  const PopupMenuItem(value: 'out', child: Text('Sign out of Google')),
                ],
              ),
          ],
          bottom: const TabBar(
            tabs: [Tab(text: 'Liked'), Tab(text: 'Playlists'), Tab(text: 'History')],
          ),
        ),
        body: const TabBarView(children: [_LikedTab(), _PlaylistsTab(), _HistoryTab()]),
      ),
    );
  }
}

/// Guest-mode prompt shown on account-only tabs.
class ConnectYouTubeCard extends ConsumerWidget {
  const ConnectYouTubeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider);
    return EmptyView(
      icon: Icons.account_circle_outlined,
      title: 'Connect your YouTube account',
      message: account.error ??
          'Sign in with Google to see your liked music and playlists. chinTunes only asks for read-only access.',
      action: account.notConfigured
          ? null
          : FilledButton.icon(
              onPressed: account.busy ? null : () => unawaited(ref.read(accountProvider.notifier).signIn()),
              icon: account.busy
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.login_rounded),
              label: const Text('Sign in with Google'),
            ),
    );
  }
}

class _LikedTab extends ConsumerWidget {
  const _LikedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(accountProvider.select((s) => s.signedIn));
    if (!signedIn) return const ConnectYouTubeCard();
    final musicOnly = ref.watch(musicOnlyProvider);
    return ref.watch(ytLikedProvider).when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(
            title: 'Couldn\'t load your liked videos',
            onRetry: () => ref.invalidate(ytLikedProvider),
          ),
          data: (items) {
            final tracks = items.where((t) => !musicOnly || t.isMusic).map((t) => t.track).toList();
            if (tracks.isEmpty) {
              return EmptyView(
                icon: Icons.thumb_up_alt_outlined,
                title: musicOnly ? 'No liked music yet' : 'No liked videos yet',
                message: musicOnly ? 'Turn off the music filter to see all liked videos.' : null,
              );
            }
            return RefreshIndicator(
              onRefresh: () => ref.refresh(ytLikedProvider.future),
              child: TrackListBody(tracks: tracks, header: pluralize(tracks.length, 'liked song')),
            );
          },
        );
  }
}

class _PlaylistsTab extends ConsumerWidget {
  const _PlaylistsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(accountProvider.select((s) => s.signedIn));
    if (!signedIn) return const ConnectYouTubeCard();
    return ref.watch(ytPlaylistsProvider).when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(
            title: 'Couldn\'t load your playlists',
            onRetry: () => ref.invalidate(ytPlaylistsProvider),
          ),
          data: (playlists) => playlists.isEmpty
              ? const EmptyView(icon: Icons.playlist_play_rounded, title: 'You have no YouTube playlists')
              : ListView.builder(
                  padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24),
                  itemCount: playlists.length,
                  itemBuilder: (context, i) => CollectionTile(
                    summary: playlists[i],
                    onTap: () => unawaited(context.push('/library/youtube/playlist', extra: playlists[i])),
                  ),
                ),
        );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(historyEntriesProvider).valueOrNull ?? const <HistoryEntry>[];
    final imported = ref.read(libraryStoreProvider).importedCount;
    final tracks = entries.map((e) => e.track).toList();
    final theme = Theme.of(context);

    return ListView.builder(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24),
      itemCount: entries.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your plays in chinTunes${imported > 0 ? ' plus ${pluralize(imported, 'imported play')}' : ''}.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'YouTube no longer shares watch history through its API. Export it from Google Takeout '
                  '(YouTube and YouTube Music → history, JSON format) and import watch-history.json.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => unawaited(importTakeoutHistory(context, ref)),
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('Import watch-history.json'),
                ),
                if (entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 32),
                    child: Center(child: Text('Songs you play will show up here.')),
                  ),
              ],
            ),
          );
        }
        final e = entries[i - 1];
        return ListTile(
          onTap: () => ref.playQueue(tracks, index: i - 1),
          leading: Artwork(url: e.track.imageUrl, size: 48, radius: 6),
          title: Text(e.track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [e.track.artist, formatRelative(e.playedAt), if (e.origin == 'takeout') 'Takeout'].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            tooltip: 'Start mix',
            icon: const Icon(Icons.radio_rounded),
            onPressed: () => unawaited(ref.startMix(context, e.track)),
          ),
        );
      },
    );
  }
}

/// A signed-in user's (possibly private) YouTube playlist.
class AccountPlaylistScreen extends ConsumerWidget {
  const AccountPlaylistScreen({super.key, required this.summary});

  final CollectionSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(summary.title)),
      body: ref.watch(ytPlaylistProvider(summary)).when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
              title: 'Couldn\'t load "${summary.title}"',
              onRetry: () => ref.invalidate(ytPlaylistProvider(summary)),
            ),
            data: (col) => col.tracks.isEmpty
                ? const EmptyView(icon: Icons.playlist_remove_rounded, title: 'This playlist is empty')
                : TrackListBody(tracks: col.tracks, header: pluralize(col.tracks.length, 'video')),
          ),
    );
  }
}

/// Small account row for Settings.
class AccountTile extends ConsumerWidget {
  const AccountTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AccountState account = ref.watch(accountProvider);
    final notifier = ref.read(accountProvider.notifier);
    if (account.signedIn) {
      final user = account.user!;
      return ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.elevated,
          backgroundImage: user.photoUrl == null ? null : NetworkImage(user.photoUrl!),
          child: user.photoUrl == null ? const Icon(Icons.person_rounded) : null,
        ),
        title: Text(user.displayName ?? user.email),
        subtitle: Text(user.email),
        trailing: TextButton(onPressed: () => unawaited(notifier.signOut()), child: const Text('Sign out')),
      );
    }
    return ListTile(
      leading: const Icon(Icons.account_circle_outlined),
      title: const Text('Google account'),
      subtitle: Text(account.error ?? 'Guest mode. Sign in to sync your YouTube likes and playlists.'),
      trailing: account.notConfigured
          ? null
          : TextButton(
              onPressed: account.busy ? null : () => unawaited(notifier.signIn()),
              child: const Text('Sign in'),
            ),
    );
  }
}
