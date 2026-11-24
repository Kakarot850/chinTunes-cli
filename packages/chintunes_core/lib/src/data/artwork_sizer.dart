import 'data_mode.dart';

/// Rewrites artwork URLs to compact thumbnails in Ultra Saver mode.
///
/// - JioSaavn `…-500x500.jpg` → `…-150x150.jpg`
/// - YouTube `i.ytimg.com/vi/<id>/<any>.jpg?…` → `…/mqdefault.jpg` (320x180, ~10 KB)
/// - Google user content `…=w544-h544-…` → `…=w120-h120-l90-rj`
/// - local `file://` artwork and other hosts are returned unchanged.
abstract final class ArtworkSizer {
  static final RegExp _saavnSize = RegExp(r'(?<=[-_])\d{2,4}x\d{2,4}(?=\.(?:jpg|jpeg|png|webp))');
  static final RegExp _ytThumb = RegExp(r'^(https?://i\d?\.ytimg\.com/vi(?:_webp)?/[^/]+/)[^/?]+\.(?:jpg|webp)(?:\?.*)?$');
  static final RegExp _googleSize = RegExp(r'=w\d+-h\d+[^/]*$');

  static String? adapt(String? url, DataMode mode) {
    if (url == null || url.isEmpty || mode != DataMode.ultraSaver) return url;
    if (url.startsWith('file:')) return url;
    if (url.contains('saavncdn.com')) return url.replaceFirst(_saavnSize, '150x150');
    final yt = _ytThumb.firstMatch(url);
    if (yt != null) return '${yt.group(1)}mqdefault.jpg';
    if (url.contains('googleusercontent.com') && _googleSize.hasMatch(url)) {
      return url.replaceFirst(_googleSize, '=w120-h120-l90-rj');
    }
    return url;
  }
}
