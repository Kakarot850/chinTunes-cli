import 'package:chintunes_core/chintunes_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';
import 'artwork.dart';
import 'track_actions.dart';

class TrackTile extends ConsumerWidget {
  const TrackTile({super.key, required this.track, required this.onTap, this.leadingIndex, this.onRemove});

  final Track track;
  final VoidCallback onTap;

  /// Show a track number instead of artwork (album pages).
  final int? leadingIndex;

  /// Extra "Remove" action (local playlists).
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCurrent = ref.watch(mediaItemProvider.select((v) => v.valueOrNull?.id == track.uid));
    final downloaded = ref.watch(downloadedIdsProvider.select((ids) => ids.contains(track.uid)));
    final theme = Theme.of(context);
    final subtitle = [
      if (track.source == TrackSource.youtube || track.source.isMetadataOnly) track.source.label,
      track.artist,
    ].join(' · ');

    return ListTile(
      onTap: onTap,
      onLongPress: () => showTrackActions(context, track, onRemove: onRemove),
      minVerticalPadding: 8,
      leading: leadingIndex != null
          ? SizedBox(
              width: 32,
              child: Center(
                child: Text(
                  '$leadingIndex',
                  style: theme.textTheme.bodyMedium?.copyWith(color: isCurrent ? AppColors.accent : null),
                ),
              ),
            )
          : Artwork(url: track.imageUrl, size: 48, radius: 6),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: isCurrent ? AppColors.accent : AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Row(
        children: [
          if (downloaded) ...[
            const Icon(Icons.download_done_rounded, size: 14, color: AppColors.success, semanticLabel: 'Downloaded'),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
      trailing: IconButton(
        tooltip: 'More options',
        icon: const Icon(Icons.more_vert_rounded),
        onPressed: () => showTrackActions(context, track, onRemove: onRemove),
      ),
    );
  }
}
