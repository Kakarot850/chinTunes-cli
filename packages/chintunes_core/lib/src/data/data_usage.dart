import 'dart:async';
import 'dart:math' as math;

import 'data_mode.dart';

enum NetworkKind { wifi, cellular, other, offline }

abstract final class NetworkPolicy {
  /// Background prefetch of the next queue item. Disabled in Ultra Saver on
  /// cellular (the next track then loads when it starts) and when offline.
  static bool allowPrefetch(DataMode mode, NetworkKind network) {
    if (network == NetworkKind.offline) return false;
    return !(mode == DataMode.ultraSaver && network == NetworkKind.cellular);
  }
}

class DataUsageSnapshot {
  const DataUsageSnapshot({
    this.sessionSavedBytes = 0,
    this.sessionUsedBytes = 0,
    this.totalSavedBytes = 0,
    this.totalUsedBytes = 0,
  });

  final int sessionSavedBytes;
  final int sessionUsedBytes;
  final int totalSavedBytes;
  final int totalUsedBytes;

  static double mb(int bytes) => bytes / (1024 * 1024);
}

/// Estimates streamed vs. saved bytes per listened second.
///
/// saved = (High-mode bytes for the listened time) − (bytes actually streamed).
/// Offline downloads and complete cache hits stream 0 bytes, so the whole
/// baseline counts as saved.
class DataUsageMeter {
  DataUsageMeter({int totalSavedBytes = 0, int totalUsedBytes = 0})
      : _totalSaved = totalSavedBytes,
        _totalUsed = totalUsedBytes;

  int _sessionSaved = 0;
  int _sessionUsed = 0;
  int _totalSaved;
  int _totalUsed;
  final StreamController<DataUsageSnapshot> _changes = StreamController<DataUsageSnapshot>.broadcast();

  Stream<DataUsageSnapshot> get changes => _changes.stream;

  DataUsageSnapshot get snapshot => DataUsageSnapshot(
        sessionSavedBytes: _sessionSaved,
        sessionUsedBytes: _sessionUsed,
        totalSavedBytes: _totalSaved,
        totalUsedBytes: _totalUsed,
      );

  static int bytesFor(int kbps, Duration listened) =>
      (kbps * 1000 / 8 * listened.inMilliseconds / 1000).round();

  void recordPlayback({
    required int? actualKbps,
    required int baselineKbps,
    required Duration listened,
    required bool fromLocal,
  }) {
    if (listened <= Duration.zero) return;
    final baseline = bytesFor(baselineKbps, listened);
    final used = fromLocal ? 0 : bytesFor(actualKbps ?? baselineKbps, listened);
    final saved = math.max(0, baseline - used);
    _sessionUsed += used;
    _totalUsed += used;
    _sessionSaved += saved;
    _totalSaved += saved;
    if (!_changes.isClosed) _changes.add(snapshot);
  }

  void resetTotals() {
    _totalSaved = 0;
    _totalUsed = 0;
    _sessionSaved = 0;
    _sessionUsed = 0;
    if (!_changes.isClosed) _changes.add(snapshot);
  }

  Map<String, int> toJson() => {'totalSavedBytes': _totalSaved, 'totalUsedBytes': _totalUsed};

  factory DataUsageMeter.fromJson(Map<dynamic, dynamic>? json) => DataUsageMeter(
        totalSavedBytes: (json?['totalSavedBytes'] as int?) ?? 0,
        totalUsedBytes: (json?['totalUsedBytes'] as int?) ?? 0,
      );

  Future<void> close() => _changes.close();
}
