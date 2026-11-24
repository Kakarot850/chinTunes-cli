/// Where a track came from. [jiosaavn] and [youtube] carry their own audio;
/// [spotify], [deezer] and [appleMusic] are metadata-only (imported
/// playlists) and play through a YouTube / JioSaavn match.
enum TrackSource {
  jiosaavn,
  youtube,
  spotify,
  local,
  deezer,
  appleMusic;

  bool get isMetadataOnly =>
      this == TrackSource.spotify || this == TrackSource.deezer || this == TrackSource.appleMusic;

  String get label => switch (this) {
        TrackSource.jiosaavn => 'JioSaavn',
        TrackSource.youtube => 'YouTube',
        TrackSource.spotify => 'Spotify',
        TrackSource.local => 'Offline',
        TrackSource.deezer => 'Deezer',
        TrackSource.appleMusic => 'Apple Music',
      };
}

TrackSource _sourceFromName(Object? name) => TrackSource.values.firstWhere(
      (s) => s.name == name,
      orElse: () => TrackSource.jiosaavn,
    );

/// Provider-agnostic track model (port of `TrackMetadata` from chinTunes-cli).
///
/// Serialised to plain JSON maps for Hive storage, so no codegen is needed.
class Track {
  const Track({
    required this.id,
    required this.source,
    required this.title,
    this.artist = 'Unknown',
    this.album = '',
    this.albumId,
    this.durationSec,
    this.year,
    this.imageUrl,
    this.mediaUrl,
    this.has320 = false,
    this.hasLyrics = false,
    this.webUrl,
    this.language,
    this.localPath,
  });

  /// Provider-native id (JioSaavn song id, YouTube video id, Spotify track id).
  final String id;
  final TrackSource source;
  final String title;
  final String artist;
  final String album;
  final String? albumId;
  final int? durationSec;
  final String? year;

  /// Hi-res artwork (500x500 for JioSaavn).
  final String? imageUrl;

  /// JioSaavn only: decrypted CDN url (any bitrate; see `JioSaavnCrypto.withBitrate`).
  final String? mediaUrl;

  /// JioSaavn `more_info["320kbps"] == "true"`.
  final bool has320;
  final bool hasLyrics;
  final String? webUrl;
  final String? language;

  /// Absolute path of an offline copy, when downloaded.
  final String? localPath;

  /// Globally unique key across providers.
  String get uid => '${source.name}:$id';

  Duration? get duration =>
      durationSec == null ? null : Duration(seconds: durationSec!);

  Track copyWith({
    String? title,
    String? artist,
    String? album,
    int? durationSec,
    String? imageUrl,
    String? mediaUrl,
    bool? has320,
    String? localPath,
  }) {
    return Track(
      id: id,
      source: source,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumId: albumId,
      durationSec: durationSec ?? this.durationSec,
      year: year,
      imageUrl: imageUrl ?? this.imageUrl,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      has320: has320 ?? this.has320,
      hasLyrics: hasLyrics,
      webUrl: webUrl,
      language: language,
      localPath: localPath ?? this.localPath,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'source': source.name,
        'title': title,
        'artist': artist,
        'album': album,
        if (albumId != null) 'albumId': albumId,
        if (durationSec != null) 'durationSec': durationSec,
        if (year != null) 'year': year,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        'has320': has320,
        'hasLyrics': hasLyrics,
        if (webUrl != null) 'webUrl': webUrl,
        if (language != null) 'language': language,
        if (localPath != null) 'localPath': localPath,
      };

  /// Accepts `Map<dynamic, dynamic>` too, because Hive returns untyped maps.
  factory Track.fromJson(Map<dynamic, dynamic> json) {
    String? str(String k) => json[k]?.toString();
    final dur = json['durationSec'];
    return Track(
      id: str('id') ?? '',
      source: _sourceFromName(json['source']),
      title: str('title') ?? '',
      artist: str('artist') ?? 'Unknown',
      album: str('album') ?? '',
      albumId: str('albumId'),
      durationSec: dur is int ? dur : int.tryParse('${dur ?? ''}'),
      year: str('year'),
      imageUrl: str('imageUrl'),
      mediaUrl: str('mediaUrl'),
      has320: json['has320'] == true,
      hasLyrics: json['hasLyrics'] == true,
      webUrl: str('webUrl'),
      language: str('language'),
      localPath: str('localPath'),
    );
  }

  @override
  bool operator ==(Object other) => other is Track && other.uid == uid;

  @override
  int get hashCode => uid.hashCode;

  @override
  String toString() => 'Track($uid, $title — $artist)';
}
