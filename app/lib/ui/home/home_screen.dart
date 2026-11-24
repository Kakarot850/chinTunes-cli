import 'dart:async';

import 'package:chintunes_core/chintunes_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../audio/playback_actions.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../data/providers.dart';
import '../widgets/artwork.dart';
import '../widgets/collection_card.dart';
import '../widgets/state_views.dart';
import '../widgets/track_actions.dart';
import '../widgets/track_tile.dart';
import '../youtube/youtube_library_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(homeFeedProvider);
    final history = ref.watch(historyProvider).valueOrNull ?? const <Track>[];
    final mixSeeds = ref.watch(mixSeedsProvider);
    final radio = ref.watch(homeRadioProvider);
    final radioTracks = radio.valueOrNull ?? const <Track>[];
    final moreForYou = radioTracks.length > 16 ? radioTracks.sublist(16) : const <Track>[];
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final List<Widget> feedSlivers = feed.when(
      loading: () => const [
        SliverToBoxAdapter(child: ShelfSkeleton()),
        SliverToBoxAdapter(child: ShelfSkeleton()),
      ],
      error: (e, _) => [
        SliverToBoxAdapter(
          child: ErrorView(
            title: 'Couldn\'t load your feed',
            onRetry: () => ref.invalidate(homeFeedProvider),
          ),
        ),
      ],
      data: (data) {
        final trending = data.trending.take(8).toList();
        return [
          if (trending.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionHeader('Trending songs')),
            SliverList.builder(
              itemCount: trending.length,
              itemBuilder: (context, i) => TrackTile(
                track: trending[i],
                onTap: () => ref.playQueue(data.trending, index: i),
              ),
            ),
          ],
          for (final section in data.sections) ...[
            SliverToBoxAdapter(child: SectionHeader(section.title)),
            SliverToBoxAdapter(
              child: Shelf(
                itemCount: section.items.length,
                itemBuilder: (context, i) {
                  final item = section.items[i];
                  return CollectionCard(
                    title: item.title,
                    subtitle: item.subtitle,
                    imageUrl: item.imageUrl,
                    onTap: () {
                      if (item.type == CollectionType.song) {
                        unawaited(ref.playSummary(context, item));
                      } else {
                        openCollection(context, item);
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ];
      },
    );

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(homeRadioProvider);
          await ref.refresh(homeFeedProvider.future);
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              title: Text('chinTunes', style: Theme.of(context).textTheme.titleLarge),
              actions: [
                const AccountButton(),
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => unawaited(context.push('/settings')),
                ),
              ],
            ),
            if (history.isNotEmpty)
              SliverToBoxAdapter(
                child: _QuickResumeBanner(
                  track: history.first,
                  onTap: () => ref.playQueue(history),
                ),
              ),
            if (radioTracks.isNotEmpty) ...[
              SectionHeader(
                'Quick picks',
                trailing: TextButton(
                  onPressed: () => ref.playQueue(radioTracks),
                  child: const Text('Play all'),
                ),
              ).toSliver(),
              SliverToBoxAdapter(child: _QuickPicks(tracks: radioTracks.take(16).toList(), all: radioTracks)),
            ] else if (radio.isLoading)
              const SliverToBoxAdapter(child: ShelfSkeleton()),
            if (mixSeeds.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SectionHeader('Your mixes')),
              SliverToBoxAdapter(
                child: Shelf(
                  itemCount: mixSeeds.length,
                  itemBuilder: (context, i) {
                    final seed = mixSeeds[i];
                    return _MixCard(seed: seed, onTap: () => unawaited(ref.startMix(context, seed)));
                  },
                ),
              ),
            ],
            if (history.length > 1) ...[
              const SliverToBoxAdapter(child: SectionHeader('Recently played')),
              SliverToBoxAdapter(
                child: Shelf(
                  itemCount: history.length,
                  itemBuilder: (context, i) => CollectionCard(
                    title: history[i].title,
                    subtitle: history[i].artist,
                    imageUrl: history[i].imageUrl,
                    onTap: () => ref.playQueue(history, index: i),
                  ),
                ),
              ),
            ],
            ...feedSlivers,
            // Endless vertical feed (YouTube-style), loads more near the end.
            if (moreForYou.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SectionHeader('More for you')),
              SliverList.builder(
                itemCount: moreForYou.length + 1,
                itemBuilder: (context, i) {
                  if (i >= moreForYou.length - 4) unawaited(ref.read(homeRadioProvider.notifier).loadMore());
                  if (i == moreForYou.length) {
                    final notifier = ref.read(homeRadioProvider.notifier);
                    return notifier.exhausted
                        ? const SizedBox(height: 8)
                        : const Padding(padding: EdgeInsets.all(16), child: LoadingView());
                  }
                  return _FeedCard(
                    track: moreForYou[i],
                    onTap: () => ref.playQueue(radioTracks, index: 16 + i),
                  );
                },
              ),
            ],
            SliverToBoxAdapter(child: SizedBox(height: bottomInset + 24)),
          ],
        ),
      ),
    );
  }
}

extension on Widget {
  Widget toSliver() => SliverToBoxAdapter(child: this);
}

/// YouTube Music-style "Quick picks": songs stacked 4 per column, swiped
/// horizontally page by page (the next page peeks in).
class _QuickPicks extends ConsumerStatefulWidget {
  const _QuickPicks({required this.tracks, required this.all});

  final List<Track> tracks;
  final List<Track> all;

  static const int rows = 4;
  static const double rowHeight = 60;

  @override
  ConsumerState<_QuickPicks> createState() => _QuickPicksState();
}

class _QuickPicksState extends ConsumerState<_QuickPicks> {
  // Kept across rebuilds so the current page doesn't reset.
  final PageController _pages = PageController(viewportFraction: 0.9);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const rows = _QuickPicks.rows;
    const rowHeight = _QuickPicks.rowHeight;
    final tracks = widget.tracks;
    final all = widget.all;
    final pages = (tracks.length / rows).ceil();
    final theme = Theme.of(context);
    return SizedBox(
      height: rows * rowHeight,
      child: PageView.builder(
        controller: _pages,
        padEnds: false,
        itemCount: pages,
        itemBuilder: (context, page) => Column(
          children: [
            for (var r = 0; r < rows; r++)
              if (page * rows + r < tracks.length)
                Builder(builder: (context) {
                  final index = page * rows + r;
                  final t = tracks[index];
                  return SizedBox(
                    height: rowHeight,
                    child: InkWell(
                      onTap: () => ref.playQueue(all, index: index),
                      onLongPress: () => unawaited(showTrackActions(context, t)),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Row(
                          children: [
                            Artwork(url: t.imageUrl, size: 48, radius: 6),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'More options',
                              icon: const Icon(Icons.more_vert_rounded, size: 20),
                              onPressed: () => unawaited(showTrackActions(context, t)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
          ],
        ),
      ),
    );
  }
}

/// Large card for the vertical "More for you" feed (YouTube home style).
class _FeedCard extends StatelessWidget {
  const _FeedCard({required this.track, required this.onTap});

  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = track.duration;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: InkWell(
        onTap: onTap,
        onLongPress: () => unawaited(showTrackActions(context, track)),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Artwork(url: track.imageUrl, radius: 12),
                  if (duration != null)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Text(formatDuration(duration), style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'More options',
                  icon: const Icon(Icons.more_vert_rounded),
                  onPressed: () => unawaited(showTrackActions(context, track)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Seed artwork with a "Mix" label; starts an endless radio on tap.
class _MixCard extends StatelessWidget {
  const _MixCard({required this.seed, required this.onTap});

  final Track seed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: CollectionCard.width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Artwork(url: seed.imageUrl, size: CollectionCard.width, radius: 10),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.background.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.radio_rounded, size: 14, color: AppColors.textPrimary),
                          SizedBox(width: 4),
                          Text('Mix', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${seed.title} Mix',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w500),
            ),
            Text('Based on ${seed.artist}', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _QuickResumeBanner extends StatelessWidget {
  const _QuickResumeBanner({required this.track, required this.onTap});

  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Artwork(url: track.imageUrl, size: 56, radius: 8),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pick up where you left off', style: theme.textTheme.bodySmall),
                      const SizedBox(height: 4),
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.play_circle_fill_rounded, size: 40, color: AppColors.textPrimary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
