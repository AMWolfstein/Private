import 'package:sqflite/sqflite.dart';
import 'package:sistrum/models/metadata_separators.dart';
import 'package:sistrum/models/tag_credit_settings.dart';
import 'package:sistrum/services/library/library_schema.dart';
import 'package:sistrum/services/library/sqlite_helpers.dart' as sqlite;

/// The tag a credit comes from. [dbName] is stored in the credits table.
enum TagCreditField {
  artist('artist'),
  albumArtist('album_artist'),
  composer('composer'),
  genre('genre');

  const TagCreditField(this.dbName);

  final String dbName;
}

/// The delimiters and protected names that decide how one tag is split.
class TagCreditRules {
  const TagCreditRules({
    this.artistDelimiters = kArtistDelimiterDefaults,
    this.genreDelimiters = kGenreDelimiterDefaults,
    this.keepTogether = const [],
  });

  factory TagCreditRules.fromSettings(TagCreditSettings settings) =>
      TagCreditRules(
        artistDelimiters: settings.artistDelimiters,
        genreDelimiters: settings.genreDelimiters,
        keepTogether: settings.keepTogether,
      );

  final List<String> artistDelimiters;
  final List<String> genreDelimiters;
  final List<String> keepTogether;

  List<String> delimitersFor(TagCreditField field) =>
      field == TagCreditField.genre ? genreDelimiters : artistDelimiters;

  @override
  bool operator ==(Object other) =>
      other is TagCreditRules &&
      _sameList(artistDelimiters, other.artistDelimiters) &&
      _sameList(genreDelimiters, other.genreDelimiters) &&
      _sameList(keepTogether, other.keepTogether);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(artistDelimiters),
    Object.hashAll(genreDelimiters),
    Object.hashAll(keepTogether),
  );
}

const _letterOrDigit = r'\p{L}\p{N}';

/// Splits one tag value into its names, in order, without duplicates.
///
/// Keep-together names are protected first, so their own separators survive.
/// Word delimiters such as `feat.` only match as whole words. A newline always
/// separates, and genres never keep names together.
List<String> splitTagCredits(
  String? raw,
  TagCreditField field,
  TagCreditRules rules,
) {
  final source = raw ?? '';
  if (source.trim().isEmpty) return const [];
  final kept = <String>[];
  var text = source;
  if (field != TagCreditField.genre) {
    for (final name in rules.keepTogether) {
      text = _protect(text, name, kept);
    }
  }
  final pattern = _delimiterPattern(rules.delimitersFor(field));
  final names = <String>[];
  final seen = <String>{};
  for (final part in text.split(pattern)) {
    final name = _restore(_stripStrayBrackets(part.trim()), kept).trim();
    if (name.isEmpty) continue;
    if (seen.add(sqlite.normalizeSearchText(name))) names.add(name);
  }
  return names;
}

/// Joins the names in [value] with [separator] for saving. An empty or invalid
/// separator keeps the value as it is.
String formatTagCreditsForSave(
  String value,
  TagCreditField field,
  TagCreditRules rules,
  String separator,
) {
  if (separator.isEmpty ||
      MetadataSeparators.validSeparator(separator) != separator) {
    return value;
  }
  final names = splitTagCredits(value, field, rules);
  if (names.isEmpty) return value;
  return names.join(separator);
}

String _escape(String value) => value.replaceAllMapped(
  RegExp(r'[.*+?^$(){}\[\]|\\/]'),
  (match) => '\\${match[0]}',
);

bool _isWord(String token) => RegExp('[$_letterOrDigit]').hasMatch(token);

RegExp _delimiterPattern(List<String> delimiters) {
  final alternatives = <String>[r'\r?\n'];
  for (final token in delimiters) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) continue;
    // A word delimiter must stand alone: no letter or digit on either side.
    alternatives.add(
      _isWord(trimmed)
          ? '(?<![$_letterOrDigit])${_escape(trimmed)}(?![$_letterOrDigit])'
          : _escape(trimmed),
    );
  }
  return RegExp(
    '\\s*(?:${alternatives.join('|')})\\s*',
    caseSensitive: false,
    unicode: true,
  );
}

/// A marker that cannot occur in a tag, standing in for a protected name.
String _marker(int index) => '\u0000$index\u0000';

String _protect(String text, String name, List<String> kept) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return text;
  final pattern = RegExp(
    '(?<![$_letterOrDigit])${_escape(trimmed)}(?![$_letterOrDigit])',
    caseSensitive: false,
    unicode: true,
  );
  return text.replaceAllMapped(pattern, (match) {
    kept.add(match[0]!);
    return _marker(kept.length - 1);
  });
}

String _restore(String part, List<String> kept) => part.replaceAllMapped(
  RegExp('\u0000(\\d+)\u0000'),
  (match) => kept[int.parse(match[1]!)],
);

/// Removes brackets left unpaired at the ends of a part, such as the `(` and
/// `)` around a feature. Balanced brackets, as in `Band (UK)`, stay.
String _stripStrayBrackets(String part) {
  final unbalanced =
      '('.allMatches(part).length != ')'.allMatches(part).length ||
      '['.allMatches(part).length != ']'.allMatches(part).length;
  if (!unbalanced) return part;
  return part.replaceAll(RegExp(r'^[()\[\]]+|[()\[\]]+$'), '').trim();
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Names for every track, derived from the visible library and kept in a TEMP
/// table so artist, album artist, composer and genre queries never split a tag
/// again. It rebuilds when the library version or the rules change.
class LibraryTagCreditsCache {
  static const tempTable = 'library_tag_credits';
  static const _pageSize = 2000;

  int? _version;
  TagCreditRules? _rules;
  Future<void>? _pending;

  /// Serialises rebuilds so concurrent queries cannot race the table swap.
  Future<void> ensure(
    Database db, {
    required int libraryVersion,
    required TagCreditRules rules,
  }) {
    final run = (_pending ?? Future<void>.value()).then(
      (_) => _ensure(db, libraryVersion, rules),
    );
    _pending = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  /// Forces the next [ensure] to rebuild, for rows changed without a scan.
  void invalidate() {
    _version = null;
    _rules = null;
  }

  Future<void> _ensure(Database db, int version, TagCreditRules rules) async {
    if (_version == version && _rules == rules) return;
    await db.execute('''
      CREATE TEMP TABLE IF NOT EXISTS $tempTable (
        item_id TEXT NOT NULL,
        field TEXT NOT NULL,
        name TEXT NOT NULL,
        name_key TEXT NOT NULL,
        position INTEGER NOT NULL
      )
    ''');
    // One transaction keeps a concurrent query from reading a half-built table.
    await db.transaction((txn) async {
      await txn.execute('DELETE FROM $tempTable');
      var after = '';
      while (true) {
        final rows = await txn.rawQuery(
          'SELECT id, artist_name, album_artist, composer, genre '
          'FROM ${LibrarySchema.visibleView} WHERE id > ? ORDER BY id LIMIT ?',
          [after, _pageSize],
        );
        if (rows.isEmpty) break;
        final batch = txn.batch();
        for (final row in rows) {
          final id = row['id'] as String;
          for (final field in TagCreditField.values) {
            final names = splitTagCredits(_rawValue(row, field), field, rules);
            for (var i = 0; i < names.length; i++) {
              batch.insert(tempTable, {
                'item_id': id,
                'field': field.dbName,
                'name': names[i],
                'name_key': sqlite.normalizeSearchText(names[i]),
                'position': i,
              });
            }
          }
        }
        await batch.commit(noResult: true);
        after = rows.last['id'] as String;
      }
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS ${tempTable}_key '
        'ON $tempTable(field, name_key)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS ${tempTable}_item ON $tempTable(item_id)',
      );
    });
    _version = version;
    _rules = rules;
  }

  /// An album artist left empty means the track artist, as the scanner stores
  /// it in album_artist_norm.
  static String? _rawValue(Map<String, Object?> row, TagCreditField field) {
    return switch (field) {
      TagCreditField.artist => row['artist_name'] as String?,
      TagCreditField.albumArtist =>
        _nonEmpty(row['album_artist'] as String?) ??
            row['artist_name'] as String?,
      TagCreditField.composer => row['composer'] as String?,
      TagCreditField.genre => row['genre'] as String?,
    };
  }

  static String? _nonEmpty(String? value) =>
      value == null || value.trim().isEmpty ? null : value;
}
