import 'package:sqflite/sqflite.dart';
import 'package:sistrum/services/library/database/library_row_mapper.dart';
import 'package:sistrum/services/library/database/library_schema.dart';
import 'package:sistrum/services/library/browse/library_tag_credits.dart';
import 'package:sistrum/services/library/database/sqlite_helpers.dart'
    as sqlite;

/// Genre or composer credits from the shared credits table, so each splits
/// exactly as the Tag separators settings say. The visible view respects
/// disabled or disconnected library sources.
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
    TagCreditField field = TagCreditField.genre,
    String? genre,
    int offset = 0,
    int limit = 40,
    required int libraryVersion,
    String sortMode = 'a-z',
  }) async {
    final size = limit.clamp(1, 100);
    await credits.ensure(db, libraryVersion: libraryVersion, rules: rules);
    const table = LibraryTagCreditsCache.tempTable;
    final descending = sortMode == 'z-a';
    final nameOrder = descending ? 'DESC' : 'ASC';
    final trackOrder = switch (sortMode) {
      'latest' => 'l.sort_added DESC, l.id',
      'oldest' => 'l.sort_added, l.id',
      'artist-asc' => 'l.artist_name_norm, l.track_name_norm, l.id',
      'artist-desc' => 'l.artist_name_norm DESC, l.track_name_norm, l.id',
      'album-asc' => 'l.album_name_norm, l.track_name_norm, l.id',
      'album-desc' => 'l.album_name_norm DESC, l.track_name_norm, l.id',
      'release-newest' => 'l.sort_release DESC, l.track_name_norm, l.id',
      'release-oldest' => 'l.sort_release, l.track_name_norm, l.id',
      _ => 'l.track_name_norm $nameOrder, l.artist_name_norm $nameOrder, l.id',
    };
    if (genre == null) {
      return db.rawQuery(
        '''
        SELECT name_key AS genre_key, MIN(name) AS name,
          COUNT(DISTINCT item_id) AS track_count
        FROM $table WHERE field = ?
        GROUP BY name_key ORDER BY name_key $nameOrder LIMIT ? OFFSET ?
      ''',
        [field.dbName, size, offset],
      );
    }
    final rows = await db.rawQuery(
      '''
      SELECT l.* FROM ${LibrarySchema.visibleView} l
      WHERE l.id IN (
        SELECT item_id FROM $table WHERE field = ? AND name_key = ?
      )
      ORDER BY $trackOrder LIMIT ? OFFSET ?
    ''',
      [field.dbName, sqlite.normalizeSearchText(genre), size, offset],
    );
    return rows.map(LibraryRowMapper.decode).toList(growable: false);
  }
}
