/// Settings → Music source.
///
/// - [auto]: search JioSaavn + YouTube; every track plays from its own source.
/// - [jiosaavn]: search JioSaavn only; YouTube/Spotify tracks are matched to a
///   JioSaavn song (falls back to YouTube when there is no match).
/// - [youtube]: search YouTube only; JioSaavn tracks (home feed, likes…) are
///   played through a YouTube match.
enum MusicSource {
  auto(label: 'Auto', description: 'JioSaavn and YouTube. Each song plays from its own source.'),
  jiosaavn(label: 'JioSaavn', description: 'JioSaavn only (up to 320 kbps). YouTube songs are matched on JioSaavn.'),
  youtube(label: 'YouTube', description: 'YouTube only. JioSaavn songs are matched on YouTube.');

  const MusicSource({required this.label, required this.description});

  final String label;
  final String description;

  bool get searchesJioSaavn => this != MusicSource.youtube;
  bool get searchesYouTube => this != MusicSource.jiosaavn;

  static MusicSource fromName(String? name) =>
      MusicSource.values.firstWhere((s) => s.name == name, orElse: () => MusicSource.auto);
}
