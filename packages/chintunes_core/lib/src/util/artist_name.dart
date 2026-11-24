/// Port of `clean_artist_name` from chinTunes-cli `syncer/core/models.py`.
///
/// Strips YouTube channel noise ("- Topic", "VEVO", "Official"...) and resolves
/// generic "Release - Topic" channels using the `Title · Artist` description line.
String cleanArtistName(String? raw, {String description = ''}) {
  if (raw == null || raw.trim().isEmpty) return 'Unknown';

  var cleaned = raw.trim();
  const noiseSuffixes = [
    r'\s*-\s*Topic$',
    r'\s+Topic$',
    r'\s+Official Channel$',
    r'\s+Official$',
    r'\s+VEVO$',
    r'\s+Records$',
    r'\s+Music$',
    r'\s+Series$',
  ];
  for (final pattern in noiseSuffixes) {
    cleaned = cleaned.replaceAll(RegExp(pattern, caseSensitive: false), '').trim();
  }

  const generic = {'release', 'various artists', 'auto-generated', 'unknown', ''};
  if (generic.contains(cleaned.toLowerCase()) && description.isNotEmpty) {
    for (final line in description.split('\n')) {
      if (!line.contains('·')) continue;
      final parts = line.split('·').map((p) => p.trim()).toList();
      if (parts.length >= 2 && parts[1].isNotEmpty) return parts[1];
    }
  }
  return cleaned.isEmpty ? 'Unknown' : cleaned;
}
