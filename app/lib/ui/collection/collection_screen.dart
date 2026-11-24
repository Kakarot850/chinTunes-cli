import 'dart:async';

import 'package:chintunes_core/chintunes_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/playback_actions.dart';
import '../../core/router/app_router.dart';
import '../../core/utils/format.dart';
import '../../data/providers.dart';
import '../widgets/artwork.dart';
import '../widgets/collection_card.dart';
import '../widgets/state_views.dart';
import '../widgets/track_tile.dart';

/// Album / playlist / artist page (also used for pasted links via [CollectionBody]).
class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key, required this.summary});

  final CollectionSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(collectionProvider(summary));
    return Scaffold(
      appBar: AppBar(),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          title: 'Couldn\'t load "${summary.title}"',
          onRetry: () => ref.invalidate(collectionProvider(summary)),
        ),
        data: (col) => CollectionBody(collection: col),
      ),
    );
  }
}

class CollectionBody extends ConsumerWidget {
  const CollectionBody({super.key, required this.collection, this.showHeaderArt = true});

  final MediaCollection collection;
  final bool showHeaderArt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = collection.summary;
    final tracks = collection.tracks;
    final theme = Theme.of(context);
    final isArtist = s.type == CollectionType.artist;
    final isAlbum = s.type == CollectionType.album;
    final meta = [
      if (s.subtitle.isNotEmpty) s.subtitle,
      if (tracks.isNotEmpty) pluralize(tracks.length, 'song'),
    ].join(' · ');

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              children: [
                if (showHeaderArt) Artwork(url: s.imageUrl, size: 200, radius: 12, circle: isArtist),
                const SizedBox(height: 16),
                Text(
                  s.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall,
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(meta, textAlign: TextAlign.center, maxLines: 2, style: theme.textTheme.bodyMedium),
                ],
                const SizedBox(height: 16),
                if (tracks.isNotEmpty)
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => ref.playQueue(tracks),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => ref.shufflePlay(tracks),
                        icon: const Icon(Icons.shuffle_rounded),
                        label: const Text('Shuffle'),
                      ),
                      if (isArtist)
                        OutlinedButton.icon(
                          onPressed: () => unawaited(ref.startMix(context, tracks.first)),
                          icon: const Icon(Icons.radio_rounded),
                          label: const Text('Start mix'),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (isArtist && tracks.isNotEmpty) const SliverToBoxAdapter(child: SectionHeader('Popular')),
        SliverList.builder(
          itemCount: tracks.length,
          itemBuilder: (context, i) => TrackTile(
            track: tracks[i],
            leadingIndex: isAlbum ? i + 1 : null,
            onTap: () => ref.playQueue(tracks, index: i),
          ),
        ),
        if (collection.related.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader('Albums')),
          SliverToBoxAdapter(
            child: Shelf(
              itemCount: collection.related.length,
              itemBuilder: (context, i) {
                final a = collection.related[i];
                return CollectionCard(
                  title: a.title,
                  subtitle: a.subtitle,
                  imageUrl: a.imageUrl,
                  onTap: () => openCollection(context, a),
                );
              },
            ),
          ),
        ],
        SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24)),
      ],
    );
  }
}
