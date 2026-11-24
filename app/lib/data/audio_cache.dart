import 'dart:io';

import 'package:chintunes_core/chintunes_core.dart';

/// Disk cache for streamed audio (`LockCachingAudioSource` targets).
///
/// One file per track per data mode: `<uid>.<mode>.audio`. just_audio writes
/// `<file>.part` while downloading and renames it to `<file>` once the whole
/// stream has been received. A complete file is played with
/// `AudioSource.file`, so replaying or scrubbing uses 0 KB of network.
class AudioCache {
  AudioCache(this.dir, {this.maxBytes = 512 * 1024 * 1024});

  final Directory dir;
  final int maxBytes;

  static String _safe(String uid) => uid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  Future<void> ensure() => dir.create(recursive: true);

  File fileFor(Track track, DataMode mode) =>
      File('${dir.path}${Platform.pathSeparator}${_safe(track.uid)}.${mode.name}.audio');

  /// A fully cached rendition (highest quality first), or null.
  File? completeFor(Track track) {
    for (final mode in [DataMode.high, DataMode.balanced, DataMode.ultraSaver]) {
      final f = fileFor(track, mode);
      if (f.existsSync() && f.lengthSync() > 0) return f;
    }
    return null;
  }

  Future<int> sizeBytes() async {
    if (!dir.existsSync()) return 0;
    var total = 0;
    await for (final e in dir.list(followLinks: false)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  Future<void> clear() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
    await ensure();
  }

  /// Least-recently-modified eviction down to [maxBytes] (run at startup).
  Future<void> prune() async {
    if (!dir.existsSync()) return;
    final files = <File>[];
    await for (final e in dir.list(followLinks: false)) {
      if (e is File) files.add(e);
    }
    var total = 0;
    final stats = <File, FileStat>{};
    for (final f in files) {
      final s = await f.stat();
      stats[f] = s;
      total += s.size;
    }
    if (total <= maxBytes) return;
    files.sort((a, b) => stats[a]!.modified.compareTo(stats[b]!.modified));
    for (final f in files) {
      if (total <= maxBytes) break;
      total -= stats[f]!.size;
      try {
        await f.delete();
      } on FileSystemException {
        // In use by the player; skip.
      }
    }
  }
}
