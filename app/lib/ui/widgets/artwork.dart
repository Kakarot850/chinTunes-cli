import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chintunes_core/chintunes_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';

/// Cover art with a decode size matched to the widget (low memory on long
/// lists), a quiet placeholder, local `file://` covers for downloads (zero
/// network) and compact thumbnails in Ultra Saver mode.
class Artwork extends ConsumerWidget {
  const Artwork({super.key, required this.url, this.size, this.radius = 8, this.circle = false});

  final String? url;

  /// Square size in logical px; null = fill parent constraints.
  final double? size;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(dataModeProvider);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = size == null ? 600 : (size! * dpr).round();
    final placeholder = ColoredBox(
      color: AppColors.elevated,
      child: Center(
        child: Icon(
          circle ? Icons.person_rounded : Icons.music_note_rounded,
          color: AppColors.textTertiary,
          size: size == null ? 48 : (size! * 0.4).clamp(14, 48).toDouble(),
        ),
      ),
    );

    final effective = ArtworkSizer.adapt(url, mode);
    final Widget image;
    if (effective == null || effective.isEmpty) {
      image = placeholder;
    } else if (effective.startsWith('file:')) {
      image = Image.file(
        File(Uri.parse(effective).toFilePath()),
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        errorBuilder: (context, error, stack) => placeholder,
      );
    } else {
      image = CachedNetworkImage(
        imageUrl: effective,
        fit: BoxFit.cover,
        memCacheWidth: cacheWidth,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (context, _) => placeholder,
        errorWidget: (context, _, error) => placeholder,
      );
    }

    final clipped = circle
        ? ClipOval(child: image)
        : ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);

    return SizedBox(width: size, height: size, child: clipped);
  }
}
