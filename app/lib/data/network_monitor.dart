import 'dart:async';

import 'package:chintunes_core/chintunes_core.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Wi-Fi vs cellular tracking for the Data Saver prefetch policy.
class NetworkMonitor {
  NetworkMonitor._();

  NetworkKind _kind = NetworkKind.wifi;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  final StreamController<NetworkKind> _changes = StreamController<NetworkKind>.broadcast();

  NetworkKind get kind => _kind;
  Stream<NetworkKind> get changes => _changes.stream;

  static Future<NetworkMonitor> start() async {
    final m = NetworkMonitor._();
    final connectivity = Connectivity();
    try {
      m._kind = map(await connectivity.checkConnectivity());
      m._sub = connectivity.onConnectivityChanged.listen((r) {
        m._kind = map(r);
        m._changes.add(m._kind);
      });
    } catch (_) {
      // Plugin unavailable (tests / unsupported platform): assume Wi-Fi.
    }
    return m;
  }

  static NetworkKind map(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi) || results.contains(ConnectivityResult.ethernet)) {
      return NetworkKind.wifi;
    }
    if (results.contains(ConnectivityResult.mobile)) return NetworkKind.cellular;
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) return NetworkKind.offline;
    return NetworkKind.other;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _changes.close();
  }
}
