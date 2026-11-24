import '../data/data_mode.dart';
import '../models/track.dart';

enum DownloadStatus { queued, downloading, paused, completed, failed }

DownloadStatus _statusFrom(Object? name) => DownloadStatus.values.firstWhere(
      (s) => s.name == name,
      orElse: () => DownloadStatus.failed,
    );

/// Persistent state of one offline download.
class DownloadTask {
  const DownloadTask({
    required this.track,
    required this.status,
    required this.dataMode,
    required this.createdAt,
    this.receivedBytes = 0,
    this.totalBytes,
    this.audioPath,
    this.coverPath,
    this.error,
    this.bitrateKbps,
    this.codec,
  });

  final Track track;
  final DownloadStatus status;
  final DataMode dataMode;
  final DateTime createdAt;
  final int receivedBytes;
  final int? totalBytes;

  /// Final audio file (set once completed).
  final String? audioPath;
  final String? coverPath;
  final String? error;
  final int? bitrateKbps;
  final String? codec;

  String get uid => track.uid;
  bool get isCompleted => status == DownloadStatus.completed;
  bool get isActive => status == DownloadStatus.queued || status == DownloadStatus.downloading;

  /// 0..1, or null when the size is unknown.
  double? get progress {
    if (isCompleted) return 1;
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0).toDouble();
  }

  DownloadTask copyWith({
    DownloadStatus? status,
    int? receivedBytes,
    int? totalBytes,
    String? audioPath,
    String? coverPath,
    String? error,
    bool clearError = false,
    int? bitrateKbps,
    String? codec,
  }) =>
      DownloadTask(
        track: track,
        status: status ?? this.status,
        dataMode: dataMode,
        createdAt: createdAt,
        receivedBytes: receivedBytes ?? this.receivedBytes,
        totalBytes: totalBytes ?? this.totalBytes,
        audioPath: audioPath ?? this.audioPath,
        coverPath: coverPath ?? this.coverPath,
        error: clearError ? null : (error ?? this.error),
        bitrateKbps: bitrateKbps ?? this.bitrateKbps,
        codec: codec ?? this.codec,
      );

  Map<String, dynamic> toJson() => {
        'track': track.toJson(),
        'status': status.name,
        'dataMode': dataMode.name,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'receivedBytes': receivedBytes,
        if (totalBytes != null) 'totalBytes': totalBytes,
        if (audioPath != null) 'audioPath': audioPath,
        if (coverPath != null) 'coverPath': coverPath,
        if (error != null) 'error': error,
        if (bitrateKbps != null) 'bitrateKbps': bitrateKbps,
        if (codec != null) 'codec': codec,
      };

  factory DownloadTask.fromJson(Map<dynamic, dynamic> json) => DownloadTask(
        track: Track.fromJson((json['track'] as Map<dynamic, dynamic>?) ?? const {}),
        status: _statusFrom(json['status']),
        dataMode: DataMode.fromName(json['dataMode']?.toString()),
        createdAt: DateTime.fromMillisecondsSinceEpoch((json['createdAt'] as int?) ?? 0),
        receivedBytes: (json['receivedBytes'] as int?) ?? 0,
        totalBytes: json['totalBytes'] as int?,
        audioPath: json['audioPath']?.toString(),
        coverPath: json['coverPath']?.toString(),
        error: json['error']?.toString(),
        bitrateKbps: json['bitrateKbps'] as int?,
        codec: json['codec']?.toString(),
      );
}
