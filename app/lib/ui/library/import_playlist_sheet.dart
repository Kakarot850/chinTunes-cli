import 'dart:async';

import 'package:chintunes_core/chintunes_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';

IconData serviceIcon(PlaylistService s) => switch (s) {
      PlaylistService.spotify => Icons.graphic_eq_rounded,
      PlaylistService.youtube => Icons.smart_display_rounded,
      PlaylistService.jiosaavn => Icons.music_note_rounded,
      PlaylistService.deezer => Icons.equalizer_rounded,
      PlaylistService.appleMusic => Icons.album_rounded,
    };

/// "Import playlist": paste a Spotify / YouTube / JioSaavn / Deezer /
/// Apple Music playlist or album link. The result is a synced playlist.
Future<void> showImportPlaylistSheet(BuildContext context, {String? initialUrl}) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: _ImportSheet(initialUrl: initialUrl, parentContext: context),
      ),
    );

class _ImportSheet extends ConsumerStatefulWidget {
  const _ImportSheet({required this.parentContext, this.initialUrl});

  final BuildContext parentContext;
  final String? initialUrl;

  @override
  ConsumerState<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends ConsumerState<_ImportSheet> {
  late final TextEditingController _url = TextEditingController(text: widget.initialUrl ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    setState(() {
      _url.text = data?.text?.trim() ?? '';
      _error = null;
    });
  }

  Future<void> _import() async {
    final url = _url.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Paste a playlist link first.');
      return;
    }
    final nav = Navigator.of(context);
    final router = GoRouter.of(widget.parentContext);
    final messenger = ScaffoldMessenger.of(widget.parentContext);
    final sync = ref.read(playlistSyncProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await sync.importUrl(url);
      nav.pop();
      router.go('/library/playlist/${p.id}');
      final service = p.sync?.ref.service.label ?? 'the service';
      messenger.showSnackBar(SnackBar(
        content: Text('Imported ${p.tracks.length} songs from $service. New songs sync automatically.'),
      ));
    } on ImportException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Import failed. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Import a playlist', style: theme.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Paste a public playlist or album link. chinTunes keeps it in sync: '
            'songs added in the other app show up here.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in PlaylistImporter.supported)
                Chip(
                  avatar: Icon(serviceIcon(s), size: 16, color: AppColors.textSecondary),
                  label: Text(s.label),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onSubmitted: (_) => unawaited(_import()),
            decoration: InputDecoration(
              labelText: 'Playlist link',
              hintText: 'https://open.spotify.com/playlist/…',
              errorText: _error,
              errorMaxLines: 3,
              suffixIcon: IconButton(
                tooltip: 'Paste link',
                icon: const Icon(Icons.content_paste_rounded),
                onPressed: _busy ? null : () => unawaited(_paste()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tidal isn\'t supported yet. Very long Spotify / Apple Music playlists import their first ~100 songs.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : () => unawaited(_import()),
              icon: _busy
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.playlist_add_rounded),
              label: Text(_busy ? 'Importing…' : 'Import and sync'),
            ),
          ),
        ],
      ),
    );
  }
}
