/// A playable audio location produced by `StreamResolver`.
class ResolvedStream {
  const ResolvedStream({
    required this.uri,
    required this.sourceLabel,
    this.headers = const {},
    this.bitrateKbps,
    this.codec,
    this.container,
    this.itag,
    this.sizeBytes,
    this.isLocal = false,
    this.expires = false,
  });

  final Uri uri;
  final Map<String, String> headers;
  final int? bitrateKbps;

  /// e.g. `AAC`, `opus`, `mp4a.40.2`.
  final String? codec;

  /// e.g. `webm`, `mp4` (drives the downloaded file extension).
  final String? container;

  /// YouTube itag (249/250/251/139/140), null for other sources.
  final int? itag;
  final int? sizeBytes;

  /// e.g. `JioSaavn`, `YouTube`, `Offline`.
  final String sourceLabel;
  final bool isLocal;

  /// True when the URL is short-lived (YouTube signed URLs, ~6h). Never persist those.
  final bool expires;

  /// File extension to use when saving this stream.
  String get fileExtension {
    final c = (container ?? '').toLowerCase();
    if (c == 'webm') return 'webm';
    if (c == 'mp4' || c == 'm4a' || (codec ?? '').toLowerCase().contains('aac')) return 'm4a';
    return c.isEmpty ? 'audio' : c;
  }

  /// Compact badge for the player UI, e.g. `JioSaavn · 320 kbps AAC`.
  String get badge {
    final parts = <String>[sourceLabel];
    final quality = [
      if (bitrateKbps != null) '$bitrateKbps kbps',
      if (codec != null && codec!.isNotEmpty) codec!,
    ].join(' ');
    if (quality.isNotEmpty) parts.add(quality);
    return parts.join(' · ');
  }
}

class StreamResolveException implements Exception {
  StreamResolveException(this.message);
  final String message;

  @override
  String toString() => 'StreamResolveException: $message';
}
