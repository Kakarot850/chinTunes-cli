import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/data_mode.dart';
import '../models/resolved_stream.dart';
import '../models/track.dart';
import 'byte_fetcher.dart';
import 'download_store.dart';
import 'download_task.dart';

typedef DownloadResolve = Future<ResolvedStream> Function(Track track, DataMode mode);

class _Job {
  bool stopped = false;
  void Function()? abort;
  final Completer<void> done = Completer<void>();

  void stop() {
    stopped = true;
    abort?.call();
  }
}

/// Offline download manager.
///
/// Layout under [root] (`<app documents>/downloads/`):
///   `<source>_<id>.part`  partial audio (resumable via HTTP Range)
///   `<source>_<id>.<ext>` final audio (`m4a` for JioSaavn/AAC, `webm` for Opus)
///   `<source>_<id>.jpg`   cover art
///   `<source>_<id>.json`  metadata sidecar (track + bitrate + codec + date)
///
/// "Background-safe": state is persisted through [DownloadStore] on every
/// status change (and every [persistInterval] while transferring). On
/// [init], interrupted `downloading` tasks are re-queued and resume from the
/// partial file's length, and completed tasks whose file vanished are
/// marked failed.
class DownloadManager {
  DownloadManager({
    required this.root,
    required DownloadStore store,
    required DownloadResolve resolve,
    required ByteFetcher fetcher,
    this.maxConcurrent = 2,
    DataMode Function()? currentMode,
    this.progressInterval = const Duration(milliseconds: 250),
    this.persistInterval = const Duration(seconds: 2),
  })  : _store = store,
        _resolve = resolve,
        _fetcher = fetcher,
        _currentMode = currentMode ?? (() => DataMode.high);

  final Directory root;
  final DownloadStore _store;
  final DownloadResolve _resolve;
  final ByteFetcher _fetcher;
  final DataMode Function() _currentMode;
  final int maxConcurrent;
  final Duration progressInterval;
  final Duration persistInterval;

  final Map<String, DownloadTask> _tasks = {};
  final Map<String, _Job> _jobs = {};
  final StreamController<List<DownloadTask>> _changes = StreamController<List<DownloadTask>>.broadcast();
  bool _initialized = false;

  Stream<List<DownloadTask>> get changes => _changes.stream;

  /// Newest first.
  List<DownloadTask> get tasks =>
      _tasks.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  DownloadTask? task(String uid) => _tasks[uid];
  bool isDownloaded(String uid) => _tasks[uid]?.isCompleted ?? false;

  /// For `StreamResolver.offlineLookup`.
  String? offlinePath(Track track) {
    final t = _tasks[track.uid];
    return (t != null && t.isCompleted) ? t.audioPath : null;
  }

  /// Returns the downloaded copy of [track] (local audio + local cover) when
  /// available, so playback and artwork need zero network requests.
  Track localize(Track track) {
    final t = _tasks[track.uid];
    if (t == null || !t.isCompleted || t.audioPath == null) return track;
    final cover = t.coverPath;
    return track.copyWith(
      localPath: t.audioPath,
      imageUrl: cover == null ? null : Uri.file(cover).toString(),
    );
  }

  /// Bytes used by completed downloads (from task metadata).
  int get completedBytes => _tasks.values
      .where((t) => t.isCompleted)
      .fold<int>(0, (sum, t) => sum + (t.totalBytes ?? t.receivedBytes));

  /// Actual bytes on disk under [root] (audio, partials, covers, sidecars).
  Future<int> diskUsageBytes() async {
    if (!root.existsSync()) return 0;
    var total = 0;
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  static String baseName(Track track) => track.uid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  File _partFile(Track t) => File('${root.path}${Platform.pathSeparator}${baseName(t)}.part');
  File _coverFile(Track t) => File('${root.path}${Platform.pathSeparator}${baseName(t)}.jpg');
  File _sidecarFile(Track t) => File('${root.path}${Platform.pathSeparator}${baseName(t)}.json');

  void _emit() {
    if (!_changes.isClosed) _changes.add(tasks);
  }

  Future<void> init() async {
    await root.create(recursive: true);
    for (final saved in await _store.loadAll()) {
      var task = saved;
      switch (saved.status) {
        case DownloadStatus.downloading:
          task = saved.copyWith(status: DownloadStatus.queued); // interrupted → resume
        case DownloadStatus.completed:
          final path = saved.audioPath;
          if (path == null || !File(path).existsSync()) {
            task = saved.copyWith(status: DownloadStatus.failed, error: 'The file was removed from storage.');
          }
        case DownloadStatus.queued || DownloadStatus.paused || DownloadStatus.failed:
          break;
      }
      if (task.status == DownloadStatus.queued || task.status == DownloadStatus.paused) {
        final part = _partFile(task.track);
        task = task.copyWith(receivedBytes: part.existsSync() ? part.lengthSync() : 0);
      }
      _tasks[task.uid] = task;
      if (!identical(task, saved)) await _store.save(task);
    }
    _initialized = true;
    _emit();
    _pump();
  }

  Future<DownloadTask> enqueue(Track track, {DataMode? mode}) async {
    final existing = _tasks[track.uid];
    if (existing != null) {
      if (existing.isCompleted || existing.isActive) return existing;
      await resume(track.uid);
      return _tasks[track.uid]!;
    }
    final task = DownloadTask(
      track: track,
      status: DownloadStatus.queued,
      dataMode: mode ?? _currentMode(),
      createdAt: DateTime.now(),
    );
    _tasks[task.uid] = task;
    await _store.save(task);
    _emit();
    _pump();
    return task;
  }

  Future<void> pause(String uid) async {
    final t = _tasks[uid];
    if (t == null || !t.isActive) return;
    _tasks[uid] = t.copyWith(status: DownloadStatus.paused); // before stop(): the job must see it
    _jobs[uid]?.stop();
    await _store.save(_tasks[uid]!);
    _emit();
  }

  Future<void> resume(String uid) async {
    final t = _tasks[uid];
    if (t == null || !(t.status == DownloadStatus.paused || t.status == DownloadStatus.failed)) return;
    _tasks[uid] = t.copyWith(status: DownloadStatus.queued, clearError: true);
    await _store.save(_tasks[uid]!);
    _emit();
    _pump();
  }

  /// Cancels (if running) and removes the task and every file it created.
  Future<void> delete(String uid) async {
    final t = _tasks.remove(uid);
    if (t == null) return;
    final job = _jobs[uid];
    if (job != null) {
      job.stop();
      await job.done.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    }
    final files = [
      _partFile(t.track),
      _coverFile(t.track),
      _sidecarFile(t.track),
      if (t.audioPath != null) File(t.audioPath!),
    ];
    for (final f in files) {
      try {
        if (f.existsSync()) await f.delete();
      } on FileSystemException {
        // Best effort; a leftover file only costs space.
      }
    }
    await _store.remove(uid);
    _emit();
    _pump();
  }

  Future<void> cancel(String uid) => delete(uid);

  Future<void> dispose() async {
    for (final job in _jobs.values) {
      job.stop();
    }
    await _changes.close();
  }

  // ------------------------------------------------------------ internals

  void _pump() {
    if (!_initialized) return;
    final waiting = _tasks.values
        .where((t) => t.status == DownloadStatus.queued && !_jobs.containsKey(t.uid))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final slots = maxConcurrent - _jobs.length;
    for (final t in waiting.take(slots < 0 ? 0 : slots)) {
      final job = _Job();
      _jobs[t.uid] = job;
      unawaited(_run(t.uid, job).whenComplete(() {
        if (identical(_jobs[t.uid], job)) _jobs.remove(t.uid);
        if (!job.done.isCompleted) job.done.complete();
        _pump();
      }));
    }
  }

  /// Publishes [t] unless the job was stopped or the task deleted meanwhile.
  DownloadTask _publish(_Job job, DownloadTask t) {
    if (job.stopped || !_tasks.containsKey(t.uid)) return t;
    _tasks[t.uid] = t;
    _emit();
    return t;
  }

  Future<void> _run(String uid, _Job job) async {
    final initial = _tasks[uid];
    if (initial == null) return;
    var task = _publish(job, initial.copyWith(status: DownloadStatus.downloading, clearError: true));
    await _store.save(task);
    final part = _partFile(task.track);
    IOSink? sink;
    var received = 0;

    try {
      final stream = await _resolve(task.track, task.dataMode);
      if (job.stopped) return;

      var start = part.existsSync() ? part.lengthSync() : 0;
      final response = await _fetcher.open(stream.uri, start: start);
      job.abort = response.abort;
      if (job.stopped) {
        response.abort();
        return;
      }
      if (start > 0 && !response.resumed) start = 0; // server ignored Range → restart
      received = start;
      final expected = response.totalBytes ?? stream.sizeBytes;
      sink = part.openWrite(mode: start > 0 ? FileMode.append : FileMode.write);
      task = _publish(
        job,
        task.copyWith(
          receivedBytes: received,
          totalBytes: expected,
          bitrateKbps: stream.bitrateKbps,
          codec: stream.codec,
        ),
      );

      var lastEmit = DateTime.now();
      var lastPersist = lastEmit;
      await for (final chunk in response.body) {
        if (job.stopped) break;
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastEmit) >= progressInterval) {
          lastEmit = now;
          task = _publish(job, task.copyWith(receivedBytes: received));
          if (now.difference(lastPersist) >= persistInterval) {
            lastPersist = now;
            await _store.save(task);
          }
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (job.stopped) {
        await _savePartialProgress(uid, received);
        return;
      }
      if (expected != null && received < expected) {
        throw const FileSystemException('Connection closed before the download finished');
      }

      final audio = File('${root.path}${Platform.pathSeparator}${baseName(task.track)}.${stream.fileExtension}');
      if (audio.existsSync()) await audio.delete();
      await part.rename(audio.path);
      final cover = await _saveCover(task.track);
      final done = task.copyWith(
        status: DownloadStatus.completed,
        receivedBytes: received,
        totalBytes: received,
        audioPath: audio.path,
        coverPath: cover?.path,
      );
      await _sidecarFile(task.track).writeAsString(jsonEncode({
        ...done.track.toJson(),
        'downloadedAt': DateTime.now().toIso8601String(),
        'bitrateKbps': done.bitrateKbps,
        'codec': done.codec,
        'dataMode': done.dataMode.name,
      }));
      if (!_tasks.containsKey(uid)) return; // deleted while finishing
      _tasks[uid] = done;
      await _store.save(done);
      _emit();
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      if (job.stopped) {
        await _savePartialProgress(uid, received);
        return;
      }
      final current = _tasks[uid];
      if (current == null) return;
      final failed = current.copyWith(
        status: DownloadStatus.failed,
        error: _friendly(e),
        receivedBytes: part.existsSync() ? part.lengthSync() : 0,
      );
      _tasks[uid] = failed;
      await _store.save(failed);
      _emit();
    }
  }

  Future<void> _savePartialProgress(String uid, int received) async {
    final current = _tasks[uid];
    if (current == null) return;
    _tasks[uid] = current.copyWith(receivedBytes: received);
    await _store.save(_tasks[uid]!);
    _emit();
  }

  Future<File?> _saveCover(Track track) async {
    final url = track.imageUrl;
    if (url == null || url.isEmpty || url.startsWith('file:')) return null;
    try {
      final res = await _fetcher.open(Uri.parse(url));
      final bytes = <int>[];
      await for (final chunk in res.body) {
        bytes.addAll(chunk);
      }
      if (bytes.isEmpty) return null;
      final file = _coverFile(track);
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (_) {
      return null; // artwork is optional
    }
  }

  static String _friendly(Object e) {
    if (e is StreamResolveException) return 'No downloadable stream was found.';
    if (e is FileSystemException) return 'Storage error: ${e.message}';
    return 'Download failed. Check your connection and try again.';
  }
}
