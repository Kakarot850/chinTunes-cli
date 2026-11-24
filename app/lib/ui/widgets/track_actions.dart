import 'dart:async';

import 'package:chintunes_core/chintunes_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/playback_actions.dart';
import '../../data/library_store.dart';
import '../../data/providers.dart';
import 'artwork.dart';

Future<void> showTrackActions(BuildContext context, Track track, {VoidCallback? onRemove}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheetContext) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85),
      child: SingleChildScrollView(
        child: _TrackActionsSheet(track: track, parentContext: context, onRemove: onRemove),
      ),
    ),
  );
}

class _TrackActionsSheet extends ConsumerWidget {
  const _TrackActionsSheet({required this.track, required this.parentContext, this.onRemove});

  final Track track;

  /// The opener's context: still mounted after this sheet closes.
  final BuildContext parentContext;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.read(audioHandlerProvider);
    final store = ref.read(libraryStoreProvider);
    final liked = ref.watch(likedIdsProvider).contains(track.uid);
    final download = ref.watch(downloadTaskProvider(track.uid));
    final messenger = ScaffoldMessenger.of(context);

    void done(String message) {
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Artwork(url: track.imageUrl, size: 48, radius: 6),
            title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.radio_rounded),
            title: const Text('Start mix'),
            subtitle: const Text('Endless radio based on this song'),
            onTap: () {
              unawaited(ref.startMix(parentContext, track));
              Navigator.of(context).pop();
            },
          ),
          if (download == null)
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('Download'),
              onTap: () {
                ref.download(parentContext, track);
                Navigator.of(context).pop();
              },
            )
          else if (download.isCompleted)
            ListTile(
              leading: const Icon(Icons.download_done_rounded),
              title: const Text('Remove download'),
              onTap: () {
                unawaited(ref.read(downloadManagerProvider).delete(track.uid));
                done('Download removed');
              },
            )
          else
            ListTile(
              leading: const Icon(Icons.downloading_rounded),
              title: Text(download.status == DownloadStatus.failed ? 'Retry download' : 'Downloading…'),
              enabled: download.status == DownloadStatus.failed || download.status == DownloadStatus.paused,
              onTap: () {
                unawaited(ref.read(downloadManagerProvider).resume(track.uid));
                done('Download resumed');
              },
            ),
          ListTile(
            leading: const Icon(Icons.playlist_play_rounded),
            title: const Text('Play next'),
            onTap: () {
              unawaited(handler.playNext(track));
              done('Playing next');
            },
          ),
          ListTile(
            leading: const Icon(Icons.queue_music_rounded),
            title: const Text('Add to queue'),
            onTap: () {
              unawaited(handler.addToQueue(track));
              done('Added to queue');
            },
          ),
          ListTile(
            leading: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded),
            title: Text(liked ? 'Remove from Liked Songs' : 'Add to Liked Songs'),
            onTap: () {
              unawaited(store.setLiked(track, !liked));
              done(liked ? 'Removed from Liked Songs' : 'Added to Liked Songs');
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add_rounded),
            title: const Text('Add to playlist'),
            onTap: () {
              Navigator.of(context).pop();
              if (parentContext.mounted) {
                unawaited(showAddToPlaylist(parentContext, store, track, messenger));
              }
            },
          ),
          if (onRemove != null)
            ListTile(
              leading: const Icon(Icons.remove_circle_outline_rounded),
              title: const Text('Remove from this playlist'),
              onTap: () {
                Navigator.of(context).pop();
                onRemove!();
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

Future<void> showAddToPlaylist(
  BuildContext context,
  LibraryStore store,
  Track track,
  ScaffoldMessengerState messenger,
) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      // Synced playlists mirror another app; local additions would be dropped on sync.
      final playlists = store.playlists().where((p) => !p.isSynced).toList();
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.6),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.add_rounded),
                title: const Text('New playlist'),
                onTap: () async {
                  final nav = Navigator.of(sheetContext);
                  final name = await promptPlaylistName(sheetContext, title: 'New playlist', confirmLabel: 'Create playlist');
                  if (name == null) return;
                  final p = await store.createPlaylist(name);
                  await store.addToPlaylist(p.id, track);
                  nav.pop();
                  messenger.showSnackBar(SnackBar(content: Text('Added to ${p.name}')));
                },
              ),
              for (final p in playlists)
                ListTile(
                  leading: const Icon(Icons.queue_music_rounded),
                  title: Text(p.name),
                  subtitle: Text('${p.tracks.length} songs'),
                  onTap: () async {
                    final nav = Navigator.of(sheetContext);
                    final added = await store.addToPlaylist(p.id, track);
                    nav.pop();
                    messenger.showSnackBar(
                      SnackBar(content: Text(added ? 'Added to ${p.name}' : 'Already in ${p.name}')),
                    );
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Name dialog with a visible label. Returns null when cancelled.
Future<String?> promptPlaylistName(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initial = '',
}) {
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) => _PlaylistNameDialog(title: title, confirmLabel: confirmLabel, initial: initial),
  );
}

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({required this.title, required this.confirmLabel, required this.initial});

  final String title;
  final String confirmLabel;
  final String initial;

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Playlist name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty ? null : _submit,
            child: Text(widget.confirmLabel),
          ),
        ),
      ],
    );
  }
}
