/// Upgrades JioSaavn artwork thumbnails (50x50 / 150x150) to 500x500 and forces
/// https (some launch-data payloads return `http://c.saavncdn.com/...`, which
/// Android blocks by default as cleartext traffic).
String? upscaleSaavnImage(String? url) {
  if (url == null || url.isEmpty) return null;
  final https = url.startsWith('http://') ? 'https://${url.substring(7)}' : url;
  return https.replaceAll('150x150', '500x500').replaceAll('50x50', '500x500');
}

/// Forces https on any URL string.
String? forceHttps(String? url) {
  if (url == null || url.isEmpty) return null;
  return url.startsWith('http://') ? 'https://${url.substring(7)}' : url;
}

/// Last non-empty path segment of a URL (the JioSaavn "token").
String? lastPathSegment(String? url) {
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  return segments.isEmpty ? null : segments.last;
}
