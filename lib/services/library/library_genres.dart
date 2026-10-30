import 'package:sqflite/sqflite.dart';
import 'package:sistrum/services/library/library_row_mapper.dart';
import 'package:sistrum/services/library/library_schema.dart';
import 'package:sistrum/services/library/library_tag_credits.dart';
import 'package:sistrum/services/library/sqlite_helpers.dart' as sqlite;

/// Genres from the shared credits table, so a genre splits exactly as the
/// Tag separators settings say. The visible view respects disabled or
/// disconnected library sources.
class LibraryGenres {
  const LibraryGenres(
    this.db, {
    required this.credits,
    this.rules = const TagCreditRules(),
  });

  final Database db;
  final LibraryTagCreditsCache credits;
  final TagCreditRules rules;

  Future<List<Map<String, dynamic>>> page({
    String? genre,
    int offset = 0,
    int limit = 40,
    required int libraryVersion,
  }) async {
    final size = limit.clamp(1, 100);
    await credits.ensure(db, libraryVersion: libraryVersion, rules: rules);
    const table = LibraryTagCreditsCache.tempTable;
    if (genre == null) {
      return db.rawQuery(
        '''
        SELECT name_key AS genre_key, MIN(name) AS name,
          COUNT(DISTINCT item_id) AS track_count
        FROM $table WHERE field = 'genre'
        GROUP BY name_key ORDER BY name_key LIMIT ? OFFSET ?
      ''',
        [size, offset],
      );
    }
    final rows = await db.rawQuery(
      '''
      SELECT l.* FROM ${LibrarySchema.visibleView} l
      WHERE l.id IN (
        SELECT item_id FROM $table WHERE field = 'genre' AND name_key = ?
      )
      ORDER BY l.track_name_norm, l.artist_name_norm, l.id LIMIT ? OFFSET ?
    ''',
      [sqlite.normalizeSearchText(genre), size, offset],
    );
    return rows.map(LibraryRowMapper.decode).toList(growable: false);
  }
}
