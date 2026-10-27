import 'package:sqflite/sqflite.dart';
import 'package:sistrum/services/sqlite_helpers.dart' as sqlite;

enum LibrarySearchKind { songs, albums, artists, playlists }

/// Each word must match, but words can occur in different metadata fields and
/// in any order. Punctuation is a separator, never a SQL/FTS operator.
class LibrarySearchQuery {
  LibrarySearchQuery(String text)
    : text = sqlite.normalizeSearchText(text),
      terms = RegExp(r'[\p{L}\p{N}][\p{L}\p{N}\p{M}]*', unicode: true)
          .allMatches(sqlite.normalizeSearchText(text))
          .map((match) => match.group(0)!)
          .toSet()
          .toList(growable: false);

  final String text;
  final List<String> terms;

  bool matches(String value) {
    final normalized = sqlite.normalizeSearchText(value);
    return terms.isNotEmpty && terms.every(normalized.contains);
  }

  int rank(String value) {
    final normalized = sqlite.normalizeSearchText(value);
    if (normalized == text) return 0;
    if (normalized.startsWith(text)) return 1;
    if (normalized.contains(text)) return 2;
    return 3;
  }

  String predicate(
    String column,
    List<Object?> args, {
    String? rowId,
    String? ftsTable,
    String? ftsContentTable,
  }) {
    if (terms.isEmpty) return '0';
    final indexed = ftsTable == null
        ? const <String>[]
        : terms.where((term) => term.runes.length >= 3).toList();
    final predicates = <String>[];
    if (indexed.isNotEmpty) {
      final tableName = ftsTable!.split('.').last;
      final matches = 'SELECT rowid FROM $ftsTable WHERE $tableName MATCH ?';
      predicates.add(
        '$rowId IN (${ftsContentTable == null ? matches : 'SELECT id FROM $ftsContentTable WHERE rowid IN ($matches)'})',
      );
      args.add(indexed.map((term) => '"$term"').join(' AND '));
    }
    for (final term in terms) {
      if (indexed.contains(term)) continue;
      predicates.add("$column LIKE ? ESCAPE '\\'");
      args.add('%$term%');
    }
    return predicates.join(' AND ');
  }

  String orderBy(String column, List<Object?> args) {
    final escaped = text
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    args.addAll([text, '$escaped%', '%$escaped%']);
    return '''CASE WHEN $column = ? THEN 0
      WHEN $column LIKE ? ESCAPE '\\' THEN 1
      WHEN $column LIKE ? ESCAPE '\\' THEN 2 ELSE 3 END''';
  }
}

class LibrarySearchHit {
  const LibrarySearchHit({
    required this.kind,
    required this.id,
    required this.title,
    this.artist = '',
    this.source = '',
    this.cover,
    this.samplePath = '',
    this.trackCount = 0,
  });

  final LibrarySearchKind kind;
  final String id;
  final String title;
  final String artist;
  final String source;
  final String? cover;
  final String samplePath;
  final int trackCount;

  factory LibrarySearchHit.fromRow(
    LibrarySearchKind kind,
    Map<String, Object?> row,
  ) => LibrarySearchHit(
    kind: kind,
    id: row['id'] as String,
    title: row['title'] as String? ?? '',
    artist: row['artist'] as String? ?? '',
    source: row['source'] as String? ?? '',
    cover: row['cover'] as String?,
    samplePath: row['sample_path'] as String? ?? '',
    trackCount: (row['track_count'] as num?)?.toInt() ?? 0,
  );
}

/// Runs bounded, ranked searches against the local library in SQLite instead
/// of copying the Library into Dart.
class LibrarySearchStore {
  const LibrarySearchStore(this.db, {required this.localFts});

  final DatabaseExecutor db;
  final bool localFts;

  Future<List<LibrarySearchHit>> search({
    required String query,
    required LibrarySearchKind kind,
    required bool includeLocal,
    int limit = 40,
    int offset = 0,
  }) async {
    final search = LibrarySearchQuery(query);
    if (search.terms.isEmpty || kind == LibrarySearchKind.playlists) return [];
    if (!includeLocal) return [];
    final args = <Object?>[];
    const alias = 'l';
    const table = 'library_visible';
    const artist = 'search_artist';
    const album = 'search_album';
    const title = 'search_track';
    final column = switch (kind) {
      LibrarySearchKind.songs => '$alias.search_text',
      LibrarySearchKind.albums => "$alias.$album || ' ' || $alias.$artist",
      LibrarySearchKind.artists => '$alias.$artist',
      LibrarySearchKind.playlists => throw StateError('Not a track index'),
    };
    final predicate = search.predicate(
      column,
      args,
      // Views do not expose their underlying table's implicit rowid.
      rowId: '$alias.id',
      ftsContentTable: 'library',
      ftsTable: kind != LibrarySearchKind.songs
          ? null
          : (localFts ? 'library_search_fts' : null),
    );
    final rows =
        '''
      SELECT 'local' AS source, $alias.id, $alias.track_name AS title,
        $alias.artist_name AS artist, $alias.album_name AS album,
        COALESCE(NULLIF($alias.album_artist, ''), $alias.artist_name) AS album_artist,
        $alias.album_key, $alias.$title AS title_key,
        $alias.$album AS album_sort, $alias.album_artist_norm AS artist_key,
        $alias.$artist AS artist_search,
        $alias.cover_path AS cover,
        $alias.file_path AS sample_path
      FROM $table $alias WHERE $predicate
    ''';
    // Album predicates use only album-level fields, preserving full track
    // counts. Albums are grouped by their normalized album key; artists merge
    // into one row per normalized album-artist key.
    final select = switch (kind) {
      LibrarySearchKind.songs => 'SELECT *, 1 AS track_count FROM ($rows)',
      LibrarySearchKind.albums =>
        '''
        SELECT source, album_key AS id, MIN(album) AS title,
          MIN(album_artist) AS artist, MAX(NULLIF(cover, '')) AS cover,
          MAX(sample_path) AS sample_path, COUNT(*) AS track_count,
          MIN(album_sort) AS title_key
        FROM ($rows) WHERE album_sort != '' GROUP BY source, album_key''',
      LibrarySearchKind.artists =>
        '''
        SELECT '' AS source, artist_key AS id, MIN(album_artist) AS title,
          MIN(album_artist) AS artist, MAX(NULLIF(cover, '')) AS cover,
          MAX(sample_path) AS sample_path, COUNT(*) AS track_count,
          MIN(artist_search) AS title_key
        FROM ($rows) WHERE artist_key != '' GROUP BY artist_key''',
      LibrarySearchKind.playlists => throw StateError('Not a track index'),
    };
    final rank = search.orderBy('title_key', args);
    final result = await db.rawQuery(
      '''
      SELECT * FROM ($select)
      ORDER BY $rank, title_key, artist, source, id
      LIMIT ? OFFSET ?
    ''',
      [...args, limit, offset],
    );
    return result.map((row) => LibrarySearchHit.fromRow(kind, row)).toList();
  }
}
