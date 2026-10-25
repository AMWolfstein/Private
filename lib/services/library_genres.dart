import 'package:sqflite/sqflite.dart';
import 'package:spotiflac_android/services/library_schema.dart';
import 'package:spotiflac_android/services/library_row_mapper.dart';
import 'package:spotiflac_android/services/sqlite_helpers.dart' as sqlite;

/// Split multi-value tags without treating names such as Hip-Hop/Rap as two genres.
/// The visible view respects disabled/disconnected library sources.
const libraryGenreTagsSql =
    '''
WITH RECURSIVE tags(id, remaining, remaining_keys, genre, genre_key) AS (
  SELECT id,
    REPLACE(REPLACE(COALESCE(genre, ''), CHAR(10), ';'), CHAR(13), ';') || ';',
    REPLACE(REPLACE(COALESCE(sort_genre, ''), CHAR(10), ';'), CHAR(13), ';') || ';',
    '', ''
  FROM ${LibrarySchema.visibleView}
  UNION ALL
  SELECT id, SUBSTR(remaining, INSTR(remaining, ';') + 1),
    SUBSTR(remaining_keys, INSTR(remaining_keys, ';') + 1),
    TRIM(SUBSTR(remaining, 1, INSTR(remaining, ';') - 1)),
    TRIM(SUBSTR(remaining_keys, 1, INSTR(remaining_keys, ';') - 1))
  FROM tags WHERE remaining != ''
), genres AS (
  SELECT DISTINCT id, genre_key, genre FROM tags
  WHERE genre != '' AND genre_key != ''
)
''';

/// Holds the genre tags of one library version in a per-connection temp table,
/// so paging no longer reruns the recursive CTE for every page (PERF-402).
class LibraryGenreTagCache {
  static const _tempTable = 'library_genre_tags';
  int? _version;
  Future<void>? _pending;

  /// Serialises (re)builds so concurrent page loads cannot race the swap.
  Future<void> ensure(Database db, int? version) {
    final run = (_pending ?? Future<void>.value()).then(
      (_) => _ensure(db, version),
    );
    _pending = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _ensure(Database db, int? version) async {
    if (_version == version) return;
    await db.execute('''
      CREATE TEMP TABLE IF NOT EXISTS $_tempTable (
        id TEXT NOT NULL,
        genre_key TEXT NOT NULL,
        genre TEXT NOT NULL
      )
    ''');
    // One transaction keeps an in-flight page from reading the table between
    // the DELETE and the INSERT.
    await db.transaction((txn) async {
      await txn.execute('DELETE FROM $_tempTable');
      await txn.execute(
        '''
        INSERT INTO $_tempTable (id, genre_key, genre)
        $libraryGenreTagsSql SELECT id, genre_key, genre FROM genres
      ''',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS $_tempTable'
        '_key ON $_tempTable(genre_key)',
      );
    });
    _version = version;
  }
}

class LibraryGenres {
  const LibraryGenres(this.db, {this.tagCache});
  final Database db;

  /// Null keeps the per-query recursive CTE (tests and uncached callers).
  final LibraryGenreTagCache? tagCache;

  Future<List<Map<String, dynamic>>> page({
    String? genre,
    int offset = 0,
    int limit = 40,
    int? libraryVersion,
  }) async {
    final size = limit.clamp(1, 100);
    final cache = tagCache;
    final useCache = cache != null && libraryVersion != null;
    if (useCache) await cache.ensure(db, libraryVersion);
    final tagsSql = useCache ? '' : libraryGenreTagsSql;
    final tagsTable = useCache ? LibraryGenreTagCache._tempTable : 'genres';
    if (genre == null) {
      return db.rawQuery(
        '''$tagsSql
        SELECT genre_key, MIN(genre) AS name, COUNT(DISTINCT id) AS track_count
        FROM $tagsTable GROUP BY genre_key ORDER BY genre_key LIMIT ? OFFSET ?
      ''',
        [size, offset],
      );
    }
    final rows = await db.rawQuery(
      '''$tagsSql
      SELECT l.* FROM ${LibrarySchema.visibleView} l
      WHERE l.id IN (SELECT id FROM $tagsTable WHERE genre_key = ?)
      ORDER BY l.track_name_norm, l.artist_name_norm, l.id LIMIT ? OFFSET ?
    ''',
      [sqlite.normalizeSearchText(genre), size, offset],
    );
    return rows.map(LibraryRowMapper.decode).toList(growable: false);
  }
}
