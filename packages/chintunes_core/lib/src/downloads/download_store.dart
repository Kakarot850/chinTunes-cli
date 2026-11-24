import 'dart:convert';
import 'dart:io';

import 'download_task.dart';

/// Persistence port for download state (Hive in the app, JSON file / memory
/// in tests and tools).
abstract interface class DownloadStore {
  Future<List<DownloadTask>> loadAll();
  Future<void> save(DownloadTask task);
  Future<void> remove(String uid);
}

class MemoryDownloadStore implements DownloadStore {
  final Map<String, Map<String, dynamic>> _rows = {};

  @override
  Future<List<DownloadTask>> loadAll() async => _rows.values.map(DownloadTask.fromJson).toList();

  @override
  Future<void> save(DownloadTask task) async {
    _rows[task.uid] = task.toJson();
  }

  @override
  Future<void> remove(String uid) async {
    _rows.remove(uid);
  }
}

/// Single JSON file, rewritten atomically (write temp + rename).
class JsonFileDownloadStore implements DownloadStore {
  JsonFileDownloadStore(this.file);

  final File file;
  Map<String, dynamic>? _cache;

  Future<Map<String, dynamic>> _read() async {
    if (_cache != null) return _cache!;
    if (!file.existsSync()) return _cache = <String, dynamic>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      _cache = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    } on FormatException {
      _cache = <String, dynamic>{};
    }
    return _cache!;
  }

  Future<void> _flush(Map<String, dynamic> data) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<List<DownloadTask>> loadAll() async =>
      (await _read()).values.whereType<Map<dynamic, dynamic>>().map(DownloadTask.fromJson).toList();

  @override
  Future<void> save(DownloadTask task) async {
    final data = await _read();
    data[task.uid] = task.toJson();
    await _flush(data);
  }

  @override
  Future<void> remove(String uid) async {
    final data = await _read();
    data.remove(uid);
    await _flush(data);
  }
}
