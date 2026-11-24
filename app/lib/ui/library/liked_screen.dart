import 'package:chintunes_core/chintunes_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/playback_actions.dart';
import '../../core/utils/format.dart';
import '../../data/providers.dart';
import '../widgets/state_views.dart';
import '../widgets/track_tile.dart';

class LikedScreen extends ConsumerWidget {
  const LikedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(likedTracksProvider).valueOrNull ?? const <Track>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Liked Songs')),
      body: liked.isEmpty
          ? const EmptyView(
              icon: Icons.favorite_border_rounded,
              title: 'No liked songs yet',
              message: 'Tap the heart on any song to save it here.',
            )
          : TrackListBody(tracks: liked, header: pluralize(liked.length, 'song')),
    );
  }
}

/// Play / Shuffle header + track list, shared by Liked and local playlists.
class TrackListBody extends ConsumerWidget {
  const TrackListBody({super.key, required this.tracks, required this.header, this.onRemove});

  final List<Track> tracks;
  final String header;
  final void Function(int index)? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24),
      itemCount: tracks.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                Expanded(child: Text(header, style: Theme.of(context).textTheme.bodyMedium)),
                OutlinedButton.icon(
                  onPressed: () => ref.shufflePlay(tracks),
                  icon: const Icon(Icons.shuffle_rounded),
                  label: const Text('Shuffle'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => ref.playQueue(tracks),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                ),
              ],
            ),
          );
        }
        final index = i - 1;
        return TrackTile(
          track: tracks[index],
          onTap: () => ref.playQueue(tracks, index: index),
          onRemove: onRemove == null ? null : () => onRemove!(index),
        );
      },
    );
  }
}
