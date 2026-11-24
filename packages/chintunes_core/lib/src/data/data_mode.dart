/// Global data-usage mode (Settings → Data Mode).
///
/// | Mode        | JioSaavn AAC | YouTube audio-only (itag)          |
/// |-------------|--------------|------------------------------------|
/// | Ultra Saver | 96 kbps      | Opus ~50 kbps (249)                |
/// | Balanced    | 160 kbps     | Opus ~70 kbps (250)                |
/// | High        | 320 kbps*    | Opus ~160 kbps (251)               |
///
/// *320 only when the API flags `320kbps`, else 160 (B-008).
enum DataMode {
  ultraSaver(
    label: 'Ultra Saver',
    description: 'About 50 kbps. Smallest artwork, no prefetch on mobile data.',
    jioSaavnKbps: 96,
    youtubeTargetKbps: 50,
  ),
  balanced(
    label: 'Balanced',
    description: '70 to 160 kbps. Good quality at about half the data of High.',
    jioSaavnKbps: 160,
    youtubeTargetKbps: 70,
  ),
  high(
    label: 'High',
    description: '160 to 320 kbps. Best quality, uses the most data.',
    jioSaavnKbps: 320,
    youtubeTargetKbps: 160,
  );

  const DataMode({
    required this.label,
    required this.description,
    required this.jioSaavnKbps,
    required this.youtubeTargetKbps,
  });

  final String label;
  final String description;
  final int jioSaavnKbps;
  final int youtubeTargetKbps;

  /// YouTube audio-only itags in preference order. Opus first (249/250/251),
  /// AAC (139 ≈ 48 kbps, 140 ≈ 128 kbps) only as a fallback. Video itags are
  /// never candidates: only `manifest.audioOnly` is considered.
  List<int> get youtubeItagPreference => switch (this) {
        DataMode.ultraSaver => const [249, 250, 251, 139, 140],
        DataMode.balanced => const [250, 251, 249, 140, 139],
        DataMode.high => const [251, 250, 140, 249, 139],
      };

  static DataMode fromName(String? name) =>
      DataMode.values.firstWhere((m) => m.name == name, orElse: () => DataMode.balanced);
}
