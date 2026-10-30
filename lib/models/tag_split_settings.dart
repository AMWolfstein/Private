/// Splits multi-name tags into names on configurable delimiters.
///
/// Artist, album artist and composer tags use [TagSplitSettings.artistDelimiters].
/// Genres use [TagSplitSettings.genreDelimiters], because "/" and "&" occur inside
/// real genre names ("Hip-Hop/Rap", "R&B/Soul").
///
/// Ported from the Sistrum Android app's ArtistSeparator. A word delimiter such as
/// "feat." or "ft" only matches on word boundaries, so "Daft Punk" is never split.
/// A backslash before a delimiter keeps it literal ("AC\/DC" stays "AC/DC").
library;

const kArtistDelimiters = [
  ';',
  '/',
  ',',
  '،',
  '+',
  '&',
  'feat.',
  'ft.',
  'featuring',
  'featured',
  'feature',
  'x',
  'with',
  'vs.',
  '、',
  '／',
  '・',
  '•',
];

/// ";" and the Arabic comma only, so correctly tagged genres stay whole.
const kGenreDelimiters = [';', '،'];

/// Newlines always separate genre entries, as they did before delimiters were configurable.
const _genreLineBreaks = ['\n', '\r'];

const _escape = '\\';
const _placeholderPrefix = '\u0000\u0001';
const _placeholderSuffix = '\u0002';

/// Which delimiters split tags, and whether splitting is on at all.
class TagSplitSettings {
  const TagSplitSettings({
    this.enabled = true,
    this.artistDelimiters = kArtistDelimiters,
    this.genreDelimiters = kGenreDelimiters,
  });

  factory TagSplitSettings.fromJson(Map<String, dynamic> json) {
    return TagSplitSettings(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      artistDelimiters: _cleanList(
        json['artist_delimiters'],
        kArtistDelimiters,
      ),
      genreDelimiters: _cleanList(json['genre_delimiters'], kGenreDelimiters),
    );
  }

  final bool enabled;
  final List<String> artistDelimiters;
  final List<String> genreDelimiters;

  bool get isDefault =>
      enabled &&
      _sameList(artistDelimiters, kArtistDelimiters) &&
      _sameList(genreDelimiters, kGenreDelimiters);

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'artist_delimiters': artistDelimiters,
    'genre_delimiters': genreDelimiters,
  };

  TagSplitSettings copyWith({
    bool? enabled,
    List<String>? artistDelimiters,
    List<String>? genreDelimiters,
  }) => TagSplitSettings(
    enabled: enabled ?? this.enabled,
    artistDelimiters: artistDelimiters ?? this.artistDelimiters,
    genreDelimiters: genreDelimiters ?? this.genreDelimiters,
  );

  /// Delimiters used for artists when splitting is on; empty keeps the whole tag.
  List<String> get activeArtistDelimiters =>
      enabled ? artistDelimiters : const [];

  /// Genre delimiters plus newlines when splitting is on, newlines alone otherwise.
  List<String> get activeGenreDelimiters => [
    if (enabled) ...genreDelimiters,
    ..._genreLineBreaks,
  ];

  /// Splits an artist, album artist or composer tag into names.
  List<String> splitArtists(String? raw) =>
      splitTagNames(raw, activeArtistDelimiters);

  /// Splits a genre tag into genre names.
  List<String> splitGenres(String? raw) =>
      splitTagNames(raw, activeGenreDelimiters);
}

/// Splits [raw] on [delimiters]. An empty list keeps the trimmed tag whole.
List<String> splitTagNames(String? raw, List<String> delimiters) {
  if (raw == null || raw.trim().isEmpty) return const [];
  // Not trimmed: a newline is a delimiter, and trimming would erase it.
  final tokens = delimiters.where((token) => token.isNotEmpty).toList();
  if (tokens.isEmpty) return [raw.trim()];

  // Escaped delimiters are swapped for placeholders, so they never split.
  final sorted = [...tokens]..sort((a, b) => b.length.compareTo(a.length));
  final escaped = <String>[];
  final buffer = StringBuffer();
  var i = 0;
  while (i < raw.length) {
    if (raw[i] == _escape && i + 1 < raw.length) {
      final rest = raw.substring(i + 1).toLowerCase();
      final token = sorted
          .where((t) => rest.startsWith(t.toLowerCase()))
          .firstOrNull;
      if (token != null) {
        escaped.add(raw.substring(i + 1, i + 1 + token.length));
        buffer
          ..write(_placeholderPrefix)
          ..writeCharCode(escaped.length - 1)
          ..write(_placeholderSuffix);
        i += 1 + token.length;
        continue;
      }
    }
    buffer.write(raw[i]);
    i++;
  }

  final names = <String>[];
  for (final segment in buffer.toString().split(_pattern(sorted))) {
    var restored = segment;
    for (var index = 0; index < escaped.length; index++) {
      restored = restored.replaceAll(
        '$_placeholderPrefix${String.fromCharCode(index)}$_placeholderSuffix',
        escaped[index],
      );
    }
    final name = cleanTagSegment(restored);
    if (name.isNotEmpty && !names.contains(name)) names.add(name);
  }
  return names;
}

final _patterns = <String, RegExp>{};

RegExp _pattern(List<String> sortedTokens) {
  final key = sortedTokens.join('\u0000');
  return _patterns.putIfAbsent(key, () {
    final parts = sortedTokens.map((token) {
      final escaped = RegExp.escape(token);
      final startsWord = _isWordChar(token.isEmpty ? '' : token[0]);
      final endsWord = _isWordChar(
        token.isEmpty ? '' : token[token.length - 1],
      );
      final prefix = startsWord ? r'(?<![\p{L}\p{N}_])' : '';
      final suffix = endsWord ? r'(?![\p{L}\p{N}_])' : '';
      return '$prefix$escaped$suffix';
    });
    return RegExp(parts.join('|'), caseSensitive: false, unicode: true);
  });
}

bool _isWordChar(String char) =>
    char.isNotEmpty && RegExp(r'[\p{L}\p{N}_]', unicode: true).hasMatch(char);

/// Trims unbalanced brackets left over from features, such as "Artist (" or
/// "(ft. Artist B)". Balanced brackets inside a name ("Band (UK)") are kept.
String cleanTagSegment(String segment) {
  var s = segment.trim();
  while (s.isNotEmpty && '([{'.contains(s[s.length - 1])) {
    s = s.substring(0, s.length - 1).trim();
  }
  while (s.isNotEmpty && ')]}'.contains(s[0])) {
    s = s.substring(1).trim();
  }
  for (final pair in const [('(', ')'), ('[', ']'), ('{', '}')]) {
    while (s.isNotEmpty &&
        s.endsWith(pair.$2) &&
        _count(s, pair.$2) > _count(s, pair.$1)) {
      s = s.substring(0, s.length - 1).trim();
    }
    while (s.isNotEmpty &&
        s.startsWith(pair.$1) &&
        _count(s, pair.$1) > _count(s, pair.$2)) {
      s = s.substring(1).trim();
    }
  }
  return s;
}

int _count(String s, String char) => char.allMatches(s).length;

List<String> _cleanList(Object? value, List<String> fallback) {
  if (value is! List) return fallback;
  final tokens = value
      .whereType<String>()
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty)
      .toSet()
      .toList(growable: false);
  return tokens.isEmpty ? fallback : tokens;
}

bool _sameList(List<String> a, List<String> b) =>
    a.length == b.length && a.every(b.contains);
