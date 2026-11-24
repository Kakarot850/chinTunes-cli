import 'package:chintunes_core/chintunes_core.dart';
import 'package:flutter/foundation.dart';

import 'library_store.dart';

/// Imports remote playlists and keeps them in sync (B-044).
///
/// Sync triggers: the "Sync" button, "Sync all", app start and every return
/// to the foreground when a playlist is older than [staleAfter]. Android
/// can't push "playlist changed" events from other apps, so this pull model
/// is how songs added in Spotify / YouTube / JioSaavn / Deezer / Apple Music
/// show up here.
class PlaylistSyncService {
  PlaylistSyncService({required PlaylistImporter importer, required LibraryStore store})
      : _importer = importer,
        _store = store;

  final PlaylistImporter _importer;
  final LibraryStore _store;

  static const Duration staleAfter = Duration(minutes: 15);

  /// Playlist ids currently syncing (drives spinners).
  final ValueNotifier<Set<String>> syncing = ValueNotifier<Set<String>>(const {});

  bool _bulkRunning = false;

  Future<LocalPlaylist> importUrl(String url) async {
    final remote = await _importer.importUrl(url);
    return _store.createSyncedPlaylist(remote);
  }

  /// Syncs one playlist; returns the diff, or throws [ImportException].
  Future<PlaylistDiff> sync(String id) async {
    final p = _store.playlist(id);
    final info = p?.sync;
    if (p == null || info == null) throw ImportException('This playlist isn\'t linked to a service.');
    if (syncing.value.contains(id)) return const PlaylistDiff(added: [], removed: [], kept: 0);
    syncing.value = {...syncing.value, id};
    try {
      final remote = await _importer.fetch(info.ref);
      return await _store.applySync(id, remote);
    } on ImportException catch (e) {
      await _store.markSyncError(id, e.message);
      rethrow;
    } catch (_) {
      const message = 'Sync failed. Check your connection and try again.';
      await _store.markSyncError(id, message);
      throw ImportException(message);
    } finally {
      syncing.value = {...syncing.value}..remove(id);
    }
  }

  /// Syncs every linked playlist (optionally only stale ones). Returns the
  /// number of new songs found. Errors are recorded per playlist.
  Future<int> syncAll({bool onlyStale = false}) async {
    if (_bulkRunning) return 0;
    _bulkRunning = true;
    var added = 0;
    try {
      final now = DateTime.now();
      for (final p in _store.syncedPlaylists()) {
        final last = p.sync!.lastSyncedAt;
        if (onlyStale && last != null && now.difference(last) < staleAfter) continue;
        try {
          added += (await sync(p.id)).added.length;
        } catch (_) {
          // Recorded on the playlist; keep going.
        }
      }
    } finally {
      _bulkRunning = false;
    }
    return added;
  }

  void dispose() => syncing.dispose();
}
