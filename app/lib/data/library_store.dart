import 'dart:async';

import 'package:chintunes_core/chintunes_core.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

/// A user-created playlist stored locally.
class LocalPlaylist {
  const LocalPlaylist({required this.id, required this.name, required this.createdAt, this.tracks = const []});

  final String id;
  final String name;
  final DateTime createdAt;
  final List<Track> tracks;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };

  factory LocalPlaylist.fromJson(Map<dynamic, dynamic> json) => LocalPlaylist(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? 'Playlist',
        createdAt: DateTime.fromMillisecondsSinceEpoch((json['createdAt'] as int?) ?? 0),
        tracks: ((json['tracks'] as List<dynamic>?) ?? const [])
            .whereType<Map<dynamic, dynamic>>()
            .map(Track.fromJson)
            .toList(),
      );
}

/// Hive-backed download registry (implements the core [DownloadStore] port).
class HiveDownloadStore implements DownloadStore {
  HiveDownloadStore(this._box);

  final Box<dynamic> _box;

  @override
  Future<List<DownloadTask>> loadAll() async =>
      _box.values.whereType<Map<dynamic, dynamic>>().map(DownloadTask.fromJson).toList();

  @override
  Future<void> save(DownloadTask task) => _box.put(task.uid, task.toJson());

  @override
  Future<void> remove(String uid) => _box.delete(uid);
}

/// Hive-backed persistence for liked songs, play history (+ play counts),
/// imported Takeout history, playlists, recent searches, settings and the
/// download registry. Values are plain JSON maps (no TypeAdapters / codegen).
class LibraryStore {
  LibraryStore._(this._liked, this._history, this._playlists, this._prefs, this._imported, this._downloads);

  static const int maxHistory = 200;
  static const int maxSearches = 12;
  static const String _searchesKey = 'recent_searches';
  static const String _dataModeKey = 'data_mode';
  static const String _dataUsageKey = 'data_usage';
  static const String _musicOnlyKey = 'yt_music_only';
  static const String _streamCacheKey = 'stream_cache_enabled';
  static const String _musicSourceKey = 'music_source';
  static const String _autoplayKey = 'autoplay_enabled';

  final Box<dynamic> _liked;
  final Box<dynamic> _history;
  final Box<dynamic> _playlists;
  final Box<dynamic> _prefs;
  final Box<dynamic> _imported;
  final Box<dynamic> _downloads;

  late final DownloadStore downloadStore = HiveDownloadStore(_downloads);

  static Future<LibraryStore> open() async {
    await Hive.initFlutter('chintunes');
    return _openBoxes();
  }

  /// For tests: plain directory, no platform channels.
  static Future<LibraryStore> openAt(String path) async {
    Hive.init(path);
    return _openBoxes();
  }

  static Future<LibraryStore> _openBoxes() async {
    final boxes = await Future.wait([
      Hive.openBox<dynamic>('liked'),
      Hive.openBox<dynamic>('history'),
      Hive.openBox<dynamic>('playlists'),
      Hive.openBox<dynamic>('prefs'),
      Hive.openBox<dynamic>('imported_history'),
      Hive.openBox<dynamic>('downloads'),
    ]);
    return LibraryStore._(boxes[0], boxes[1], boxes[2], boxes[3], boxes[4], boxes[5]);
  }

  Future<void> close() async {
    await Future.wait([
      _liked.close(),
      _history.close(),
      _playlists.close(),
      _prefs.close(),
      _imported.close(),
      _downloads.close(),
    ]);
  }

  static int _now() => DateTime.now().microsecondsSinceEpoch;

  static int _at(Object? v) => v is Map ? ((v['at'] as int?) ?? 0) : 0;

  static List<Track> _sortedTracks(Box<dynamic> box) {
    final entries = box.values.whereType<Map<dynamic, dynamic>>().toList()
      ..sort((a, b) => _at(b).compareTo(_at(a)));
    return entries
        .map((m) => m['track'])
        .whereType<Map<dynamic, dynamic>>()
        .map(Track.fromJson)
        .toList();
  }

  static Stream<T> _watch<T>(Box<dynamic> box, T Function() read, {String? key}) async* {
    yield read();
    await for (final _ in box.watch(key: key)) {
      yield read();
    }
  }

  // ------------------------------------------------------------------ liked

  bool isLiked(String uid) => _liked.containsKey(uid);

  List<Track> likedTracks() => _sortedTracks(_liked);

  Stream<List<Track>> watchLiked() => _watch(_liked, likedTracks);

  Future<void> setLiked(Track track, bool liked) async {
    if (liked) {
      await _liked.put(track.uid, {'at': _now(), 'track': track.toJson()});
    } else {
      await _liked.delete(track.uid);
    }
  }

  Future<void> toggleLike(Track track) => setLiked(track, !isLiked(track.uid));

  // ---------------------------------------------------------------- history

  List<Track> recentlyPlayed() => _sortedTracks(_history);

  Stream<List<Track>> watchHistory() => _watch(_history, recentlyPlayed);

  int playCount(String uid) {
    final v = _history.get(uid);
    return v is Map ? ((v['count'] as int?) ?? 1) : 0;
  }

  /// Most-played first (ties: most recent first). Seeds "Your Mixes".
  List<Track> topTracks({int limit = 10}) {
    final entries = _history.values.whereType<Map<dynamic, dynamic>>().toList()
      ..sort((a, b) {
        final byCount = ((b['count'] as int?) ?? 1).compareTo((a['count'] as int?) ?? 1);
        return byCount != 0 ? byCount : _at(b).compareTo(_at(a));
      });
    return entries
        .take(limit)
        .map((m) => m['track'])
        .whereType<Map<dynamic, dynamic>>()
        .map(Track.fromJson)
        .toList();
  }

  Future<void> recordPlay(Track track) async {
    final count = playCount(track.uid) + 1;
    await _history.put(track.uid, {'at': _now(), 'count': count, 'track': track.toJson()});
    if (_history.length > maxHistory) {
      final entries = _history.toMap().entries.toList()..sort((a, b) => _at(a.value).compareTo(_at(b.value)));
      final excess = entries.take(_history.length - maxHistory).map((e) => e.key);
      await _history.deleteAll(excess);
    }
  }

  Future<void> clearHistory() => _history.clear();

  // ------------------------------------------------- imported (Takeout) history

  int get importedCount => _imported.length;

  /// Stores Takeout entries; returns how many were new (re-imports are idempotent).
  Future<int> importHistory(List<HistoryEntry> entries) async {
    final rows = <String, Map<String, dynamic>>{};
    for (final e in entries) {
      final key = '${e.track.uid}@${e.playedAt.millisecondsSinceEpoch}';
      if (_imported.containsKey(key)) continue;
      rows[key] = {
        'at': e.playedAt.microsecondsSinceEpoch,
        'music': e.isMusic,
        'track': e.track.toJson(),
      };
    }
    if (rows.isNotEmpty) await _imported.putAll(rows);
    return rows.length;
  }

  Future<void> clearImportedHistory() => _imported.clear();

  /// Local plays + imported Takeout plays, newest first.
  List<HistoryEntry> combinedHistory({int limit = 500, bool musicOnly = false}) {
    HistoryEntry? entry(Object? raw, String origin) {
      if (raw is! Map) return null;
      final track = raw['track'];
      if (track is! Map) return null;
      return HistoryEntry(
        track: Track.fromJson(track),
        playedAt: DateTime.fromMicrosecondsSinceEpoch(_at(raw), isUtc: true),
        isMusic: origin == 'local' || raw['music'] == true,
        origin: origin,
      );
    }

    final all = <HistoryEntry>[
      ..._history.values.map((v) => entry(v, 'local')).whereType<HistoryEntry>(),
      ..._imported.values.map((v) => entry(v, 'takeout')).whereType<HistoryEntry>(),
    ];
    final filtered = musicOnly ? all.where((e) => e.isMusic).toList() : all;
    filtered.sort((a, b) => b.playedAt.compareTo(a.playedAt));
    return filtered.take(limit).toList();
  }

  Stream<List<HistoryEntry>> watchCombinedHistory({bool musicOnly = false}) async* {
    yield combinedHistory(musicOnly: musicOnly);
    await for (final _ in _mergeWatch()) {
      yield combinedHistory(musicOnly: musicOnly);
    }
  }

  /// Hive has no multi-box watch: merge both boxes' event streams.
  Stream<void> _mergeWatch() => StreamGroupLite.merge([_history.watch(), _imported.watch()]);

  // --------------------------------------------------------------- searches

  List<String> recentSearches() =>
      ((_prefs.get(_searchesKey) as List<dynamic>?) ?? const []).map((e) => e.toString()).toList();

  Stream<List<String>> watchRecentSearches() => _watch(_prefs, recentSearches, key: _searchesKey);

  Future<void> addSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final list = recentSearches()..removeWhere((e) => e.toLowerCase() == q.toLowerCase());
    list.insert(0, q);
    await _prefs.put(_searchesKey, list.take(maxSearches).toList());
  }

  Future<void> removeSearch(String query) async {
    final list = recentSearches()..remove(query);
    await _prefs.put(_searchesKey, list);
  }

  Future<void> clearSearches() => _prefs.put(_searchesKey, <String>[]);

  // --------------------------------------------------------------- settings

  DataMode dataMode() => DataMode.fromName(_prefs.get(_dataModeKey)?.toString());

  Future<void> setDataMode(DataMode mode) => _prefs.put(_dataModeKey, mode.name);

  Map<dynamic, dynamic>? dataUsage() {
    final v = _prefs.get(_dataUsageKey);
    return v is Map ? v : null;
  }

  Future<void> saveDataUsage(Map<String, int> json) => _prefs.put(_dataUsageKey, json);

  MusicSource musicSource() => MusicSource.fromName(_prefs.get(_musicSourceKey)?.toString());

  Future<void> setMusicSource(MusicSource source) => _prefs.put(_musicSourceKey, source.name);

  bool autoplayEnabled() => (_prefs.get(_autoplayKey) as bool?) ?? true;

  Future<void> setAutoplayEnabled(bool value) => _prefs.put(_autoplayKey, value);

  bool streamCacheEnabled() => (_prefs.get(_streamCacheKey) as bool?) ?? true;

  Future<void> setStreamCacheEnabled(bool value) => _prefs.put(_streamCacheKey, value);

  bool youtubeMusicOnly() => (_prefs.get(_musicOnlyKey) as bool?) ?? true;

  Future<void> setYoutubeMusicOnly(bool value) => _prefs.put(_musicOnlyKey, value);

  // -------------------------------------------------------------- playlists

  List<LocalPlaylist> playlists() {
    final list = _playlists.values.whereType<Map<dynamic, dynamic>>().map(LocalPlaylist.fromJson).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Stream<List<LocalPlaylist>> watchPlaylists() => _watch(_playlists, playlists);

  LocalPlaylist? playlist(String id) {
    final raw = _playlists.get(id);
    return raw is Map ? LocalPlaylist.fromJson(raw) : null;
  }

  Future<LocalPlaylist> createPlaylist(String name) async {
    final clean = name.trim().isEmpty ? 'New playlist' : name.trim();
    final p = LocalPlaylist(id: 'pl_${_now()}', name: clean, createdAt: DateTime.now());
    await _playlists.put(p.id, p.toJson());
    return p;
  }

  Future<void> renamePlaylist(String id, String name) async {
    final p = playlist(id);
    if (p == null || name.trim().isEmpty) return;
    await _playlists.put(id, LocalPlaylist(id: id, name: name.trim(), createdAt: p.createdAt, tracks: p.tracks).toJson());
  }

  Future<void> deletePlaylist(String id) => _playlists.delete(id);

  /// Returns false when the track was already in the playlist.
  Future<bool> addToPlaylist(String id, Track track) async {
    final p = playlist(id);
    if (p == null || p.tracks.contains(track)) return false;
    await _playlists.put(
      id,
      LocalPlaylist(id: id, name: p.name, createdAt: p.createdAt, tracks: [...p.tracks, track]).toJson(),
    );
    return true;
  }

  Future<void> removeFromPlaylist(String id, int index) async {
    final p = playlist(id);
    if (p == null || index < 0 || index >= p.tracks.length) return;
    final tracks = [...p.tracks]..removeAt(index);
    await _playlists.put(id, LocalPlaylist(id: id, name: p.name, createdAt: p.createdAt, tracks: tracks).toJson());
  }
}

/// Tiny stream merge (avoids an extra `async` package dependency).
abstract final class StreamGroupLite {
  static Stream<void> merge(List<Stream<Object?>> streams) {
    late final StreamController<void> controller;
    final subs = <StreamSubscription<Object?>>[];
    controller = StreamController<void>(
      onListen: () {
        for (final s in streams) {
          subs.add(s.listen((_) => controller.add(null)));
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return controller.stream;
  }
}
