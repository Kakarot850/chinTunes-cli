import 'package:chintunes_core/chintunes_core.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import 'artwork.dart';

/// Square card used in horizontal shelves.
class CollectionCard extends StatelessWidget {
  const CollectionCard({super.key, required this.title, required this.subtitle, required this.imageUrl, required this.onTap, this.circle = false});

  final String title;
  final String subtitle;
  final String? imageUrl;
  final VoidCallback onTap;
  final bool circle;

  static const double width = 140;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: circle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Artwork(url: imageUrl, size: width, radius: 10, circle: circle),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: circle ? TextAlign.center : TextAlign.start,
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w500),
            ),
            if (subtitle.isNotEmpty)
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Horizontal shelf of cards.
class Shelf extends StatelessWidget {
  const Shelf({super.key, required this.itemCount, required this.itemBuilder, this.height = 204});

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: itemCount,
          separatorBuilder: (context, i) => const SizedBox(width: 12),
          itemBuilder: itemBuilder,
        ),
      );
}

/// Row tile for albums / playlists / artists in search results.
class CollectionTile extends StatelessWidget {
  const CollectionTile({super.key, required this.summary, required this.onTap});

  final CollectionSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isArtist = summary.type == CollectionType.artist;
    final kind = switch (summary.type) {
      CollectionType.album => 'Album',
      CollectionType.playlist => 'Playlist',
      CollectionType.artist => 'Artist',
      CollectionType.song => 'Song',
      CollectionType.unknown => '',
    };
    final details = [
      if (!isArtist) kind,
      if (summary.subtitle.isNotEmpty && summary.subtitle != kind) summary.subtitle,
      if (summary.songCount != null && summary.songCount! > 0) pluralize(summary.songCount!, 'song'),
    ].join(' · ');

    return ListTile(
      onTap: onTap,
      minVerticalPadding: 8,
      leading: Artwork(url: summary.imageUrl, size: 52, radius: 6, circle: isArtist),
      title: Text(summary.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(details.isEmpty ? kind : details, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}
