import 'collection.dart';
import 'track.dart';

class HomeSection {
  const HomeSection({required this.key, required this.title, required this.items});

  /// Source module key from `webapi.getLaunchData` (e.g. `charts`).
  final String key;
  final String title;
  final List<CollectionSummary> items;
}

class HomeFeed {
  const HomeFeed({required this.trending, required this.sections});

  /// `content.getTrending` songs (playable directly).
  final List<Track> trending;
  final List<HomeSection> sections;

  static const empty = HomeFeed(trending: [], sections: []);
}
