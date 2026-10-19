import 'package:sqflite/sqflite.dart';
import 'package:spotiflac_android/services/library_schema.dart';
import 'package:spotiflac_android/services/library_row_mapper.dart';

/// Split multi-value tags without treating names such as Hip-Hop/Rap as two genres.
/// The visible view respects disabled/disconnected library sources.
const libraryGenreTagsSql =
    '''
WITH RECURSIVE tags(id, remaining, genre) AS (
  SELECT id, REPLACE(REPLACE(COALESCE(genre, ''), CHAR(10), ';'), CHAR(13), ';') || ';', ''
  FROM ${LibrarySchema.visibleView}
  UNION ALL
  SELECT id, SUBSTR(remaining, INSTR(remaining, ';') + 1),
    TRIM(SUBSTR(remaining, 1, INSTR(remaining, ';') - 1))
  FROM tags WHERE remaining != ''
), genres AS (
  SELECT DISTINCT id, LOWER(genre) AS genre_key, genre FROM tags WHERE genre != ''
)
''';

class LibraryGenres {
  const LibraryGenres(this.db);
  final Database db;
  Future<List<Map<String, dynamic>>> page({
    String? genre,
    int offset = 0,
    int limit = 40,
  }) async {
    final size = limit.clamp(1, 100);
    if (genre == null) {
      return db.rawQuery(
        '''$libraryGenreTagsSql
        SELECT genre_key, MIN(genre) AS name, COUNT(DISTINCT id) AS track_count
        FROM genres GROUP BY genre_key ORDER BY genre_key LIMIT ? OFFSET ?
      ''',
        [size, offset],
      );
    }
    final rows = await db.rawQuery(
      '''$libraryGenreTagsSql
      SELECT l.* FROM ${LibrarySchema.visibleView} l
      WHERE l.id IN (SELECT id FROM genres WHERE genre_key = ?)
      ORDER BY l.track_name_norm, l.artist_name_norm, l.id LIMIT ? OFFSET ?
    ''',
      [genre, size, offset],
    );
    return rows.map(LibraryRowMapper.decode).toList(growable: false);
  }
}
