/// Per-field tag formatting applied when local tags are saved. Empty values keep the tag as is.
class MetadataSeparators {
  static const fields = ['artist', 'album_artist', 'composer', 'genre'];
  final String artist;
  final String albumArtist;
  final String composer;
  final String genre;

  const MetadataSeparators({
    this.artist = '',
    this.albumArtist = '',
    this.composer = '',
    this.genre = '',
  });

  factory MetadataSeparators.fromJson(Map<String, dynamic> json) =>
      MetadataSeparators(
        artist: validSeparator(json['artist']),
        albumArtist: validSeparator(json['album_artist']),
        composer: validSeparator(json['composer']),
        genre: validSeparator(json['genre']),
      );

  static String validSeparator(Object? value) {
    if (value is! String ||
        value.length > 16 ||
        value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      return '';
    }
    return value;
  }

  Map<String, String> toJson() => {
    'artist': artist,
    'album_artist': albumArtist,
    'composer': composer,
    'genre': genre,
  };

  bool get isDefault => toJson().values.every((value) => value.isEmpty);

  MetadataSeparators withField(String field, String separator) =>
      MetadataSeparators.fromJson({...toJson(), field: separator});

  /// The one value shared by artist, album artist and composer in settings.
  /// Settings saved before the shared value kept three; the first non-empty
  /// one stands for all of them.
  String get names {
    for (final value in [artist, albumArtist, composer]) {
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  /// Writes [separator] to artist, album artist and composer together.
  MetadataSeparators withNames(String separator) =>
      MetadataSeparators.fromJson({
        ...toJson(),
        'artist': separator,
        'album_artist': separator,
        'composer': separator,
      });

  /// The separator for a tag field, using the shared value for name fields.
  String forField(String field) => field == 'genre' ? genre : names;
}
