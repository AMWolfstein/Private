import 'package:sqflite/sqflite.dart';
import 'package:sistrum/models/tag_split_settings.dart';
import 'package:sistrum/services/library/library_schema.dart';
import 'package:sistrum/services/library/library_row_mapper.dart';
import 'package:sistrum/services/library/sqlite_helpers.dart' as sqlite;

/// Holds the genre tags of one library version in a per-connection temp table,
/// so paging does not split every track's genres again for each page (PERF-402).
///
/// Genres are split in Dart with the configured genre delimiters, so the cache
/// also rebuilds when those delimiters change.
class LibraryGenreTagCache {
  static const _tempTable = 'library_genre_tags';
  String? _key;
  Future<void>? _pending;

  /// Serialises (re)builds so concurrent page loads cannot race the swap.
  Future<void> ensure(Database db, int? version, TagSplitSettings split) {
    final run = (_pending ?? Future<void>.value()).then(
      (_) => _ensure(db, version, split),
    );
    _pending = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _ensure(
    Database db,
    int? version,
    TagSplitSettings split,
  ) async {
    final key = '$version|${split.activeGenreDelimiters.join('\u0000')}';
    if (_key == key) return;
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
      final tracks = await txn.rawQuery(
        'SELECT id, genre FROM ${LibrarySchema.visibleView}',
      );
      final batch = txn.batch();
      final seen = <String>{};
      for (final track in tracks) {
        final id = track['id'] as String;
        for (final name in split.splitGenres(track['genre'] as String?)) {
          final genreKey = sqlite.normalizeSearchText(name);
          if (genreKey.isEmpty || !seen.add('$id\u0000$genreKey')) continue;
          batch.insert(_tempTable, {
            'id': id,
            'genre_key': genreKey,
            'genre': name,
          });
        }
      }
      await batch.commit(noResult: true);
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS ${_tempTable}_key ON $_tempTable(genre_key)',
      );
    });
    _key = key;
  }
}

class LibraryGenres {
  const LibraryGenres(
    this.db, {
    this.tagCache,
    this.split = const TagSplitSettings(),
  });
  final Database db;

  /// Null, or no library version, rebuilds the genre tags for each call.
  final LibraryGenreTagCache? tagCache;

  /// Which delimiters split multi-genre tags.
  final TagSplitSettings split;

  Future<List<Map<String, dynamic>>> page({
    String? genre,
    int offset = 0,
    int limit = 40,
    int? libraryVersion,
  }) async {
    final size = limit.clamp(1, 100);
    final cache = tagCache != null && libraryVersion != null
        ? tagCache!
        : LibraryGenreTagCache();
    await cache.ensure(db, libraryVersion, split);
    const table = LibraryGenreTagCache._tempTable;
    if (genre == null) {
      return db.rawQuery(
        '''
        SELECT genre_key, MIN(genre) AS name, COUNT(DISTINCT id) AS track_count
        FROM $table GROUP BY genre_key ORDER BY genre_key LIMIT ? OFFSET ?
      ''',
        [size, offset],
      );
    }
    final rows = await db.rawQuery(
      '''
      SELECT l.* FROM ${LibrarySchema.visibleView} l
      WHERE l.id IN (SELECT id FROM $table WHERE genre_key = ?)
      ORDER BY l.track_name_norm, l.artist_name_norm, l.id LIMIT ? OFFSET ?
    ''',
      [sqlite.normalizeSearchText(genre), size, offset],
    );
    return rows.map(LibraryRowMapper.decode).toList(growable: false);
  }
}
