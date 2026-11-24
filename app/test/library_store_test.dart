import 'dart:io';

import 'package:chintunes/data/library_store.dart';
import 'package:chintunes_core/chintunes_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

Track track(String id) => Track(id: id, source: TrackSource.jiosaavn, title: 'Song $id', artist: 'Artist');

void main() {
  late Directory dir;
  late LibraryStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('chintunes_store_test');
    store = await LibraryStore.openAt(dir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('likes toggle and list newest first', () async {
    await store.toggleLike(track('a'));
    await store.toggleLike(track('b'));
    expect(store.isLiked('jiosaavn:a'), isTrue);
    expect(store.likedTracks().map((t) => t.id), ['b', 'a']);

    await store.toggleLike(track('a'));
    expect(store.isLiked('jiosaavn:a'), isFalse);
    expect(store.likedTracks().single.id, 'b');
  });

  test('history keeps the most recent plays and dedupes', () async {
    for (var i = 0; i < LibraryStore.maxHistory + 5; i++) {
      await store.recordPlay(track('t$i'));
    }
    await store.recordPlay(track('t0')); // replay moves to front
    final recent = store.recentlyPlayed();
    expect(recent.length, LibraryStore.maxHistory);
    expect(recent.first.id, 't0');
  });

  test('play counts drive topTracks (Your Mixes seeds)', () async {
    await store.recordPlay(track('a'));
    await store.recordPlay(track('b'));
    await store.recordPlay(track('b'));
    await store.recordPlay(track('c'));
    expect(store.playCount('jiosaavn:b'), 2);
    expect(store.topTracks(limit: 2).map((t) => t.id), ['b', 'c']);
  });

  test('data mode and data-usage totals persist', () async {
    expect(store.dataMode(), DataMode.balanced); // default
    await store.setDataMode(DataMode.ultraSaver);
    expect(store.dataMode(), DataMode.ultraSaver);
    await store.saveDataUsage({'totalSavedBytes': 42, 'totalUsedBytes': 7});
    expect(DataUsageMeter.fromJson(store.dataUsage()).snapshot.totalSavedBytes, 42);
  });

  test('Takeout import is idempotent and merges with local history', () async {
    final entries = [
      HistoryEntry(
        track: const Track(id: 'yt1', source: TrackSource.youtube, title: 'Old play'),
        playedAt: DateTime.utc(2024, 5, 2),
        isMusic: true,
        origin: 'takeout',
      ),
      HistoryEntry(
        track: const Track(id: 'yt2', source: TrackSource.youtube, title: 'Vlog'),
        playedAt: DateTime.utc(2024, 5, 1),
        isMusic: false,
        origin: 'takeout',
      ),
    ];
    expect(await store.importHistory(entries), 2);
    expect(await store.importHistory(entries), 0);
    await store.recordPlay(track('local'));

    final all = store.combinedHistory();
    expect(all.map((e) => e.track.id), ['local', 'yt1', 'yt2']);
    expect(all.first.origin, 'local');
    expect(store.combinedHistory(musicOnly: true).map((e) => e.track.id), ['local', 'yt1']);
  });

  test('Hive download store round-trips tasks', () async {
    final task = DownloadTask(
      track: track('d1'),
      status: DownloadStatus.completed,
      dataMode: DataMode.high,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      receivedBytes: 100,
      totalBytes: 100,
      audioPath: '/tmp/d1.m4a',
    );
    await store.downloadStore.save(task);
    final loaded = (await store.downloadStore.loadAll()).single;
    expect(loaded.uid, 'jiosaavn:d1');
    expect(loaded.status, DownloadStatus.completed);
    expect(loaded.audioPath, '/tmp/d1.m4a');
    await store.downloadStore.remove(task.uid);
    expect(await store.downloadStore.loadAll(), isEmpty);
  });

  test('synced playlist: import, mirror sync with diff, edits keep the link, stop syncing', () async {
    Track sp(String id) => Track(id: id, source: TrackSource.spotify, title: 'Song $id');
    final ref = PlaylistImporter.parseUrl('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M')!;
    final p = await store.createSyncedPlaylist(
      RemotePlaylist(ref: ref, title: 'Top Hits', tracks: [sp('a'), sp('b')]),
    );
    expect(p.isSynced, isTrue);
    expect(store.playlistForRef(ref)!.id, p.id);

    // Upstream added c, removed a.
    final diff = await store.applySync(p.id, RemotePlaylist(ref: ref, title: 'Top Hits', tracks: [sp('b'), sp('c')]));
    expect(diff.added.map((t) => t.id), ['c']);
    expect(diff.removed.map((t) => t.id), ['a']);
    final synced = store.playlist(p.id)!;
    expect(synced.tracks.map((t) => t.id), ['b', 'c']);
    expect(synced.sync!.lastSummary, '+1 new, −1 removed');
    expect(synced.sync!.lastSyncedAt, isNotNull);

    // Rename must not drop the sync link (copyWith).
    await store.renamePlaylist(p.id, 'My Top Hits');
    expect(store.playlist(p.id)!.isSynced, isTrue);

    // Re-importing the same link updates the existing mirror.
    final again = await store.createSyncedPlaylist(RemotePlaylist(ref: ref, title: 'Top Hits', tracks: [sp('c')]));
    expect(again.id, p.id);
    expect(store.syncedPlaylists(), hasLength(1));

    await store.markSyncError(p.id, 'offline');
    expect(store.playlist(p.id)!.sync!.lastError, 'offline');

    await store.stopSyncing(p.id);
    expect(store.playlist(p.id)!.isSynced, isFalse);
    expect(store.playlist(p.id)!.tracks.map((t) => t.id), ['c']);
  });

  test('recent searches dedupe case-insensitively and cap', () async {
    await store.addSearch('Arijit');
    await store.addSearch('lofi');
    await store.addSearch('arijit');
    expect(store.recentSearches(), ['arijit', 'lofi']);
    for (var i = 0; i < 20; i++) {
      await store.addSearch('q$i');
    }
    expect(store.recentSearches().length, LibraryStore.maxSearches);
    await store.clearSearches();
    expect(store.recentSearches(), isEmpty);
  });

  test('playlists CRUD', () async {
    final p = await store.createPlaylist('  Gym Hits ');
    expect(p.name, 'Gym Hits');
    expect(await store.addToPlaylist(p.id, track('a')), isTrue);
    expect(await store.addToPlaylist(p.id, track('a')), isFalse);
    await store.addToPlaylist(p.id, track('b'));
    expect(store.playlist(p.id)!.tracks.map((t) => t.id), ['a', 'b']);

    await store.removeFromPlaylist(p.id, 0);
    expect(store.playlist(p.id)!.tracks.single.id, 'b');

    await store.renamePlaylist(p.id, 'Roadtrip');
    expect(store.playlists().single.name, 'Roadtrip');

    await store.deletePlaylist(p.id);
    expect(store.playlists(), isEmpty);
  });
}
