import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sistrum/services/library/library_collections_models.dart';
import 'package:sistrum/services/library/library_collections_schema.dart';
import 'package:sistrum/services/library/sqlite_native_snapshot.dart';
import 'package:sistrum/services/native/native_data_jobs.dart';
import 'package:sistrum/utils/logger.dart';

final _log = AppLogger('LibraryCollectionsDb');

Future<LibraryCollectionsSnapshot> readDartSnapshot(Database db) {
  return db.transaction((txn) async {
    final lovedRows = await _readDateOrderedRows(txn, tableLoved, 'added_at');
    final playlistRows = await _readDateOrderedRows(
      txn,
      tablePlaylists,
      'created_at',
      projection:
          '''p.*,
      CASE WHEN p.cover_image_path IS NULL OR p.cover_image_path = '' THEN (
        SELECT pt.track_json
        FROM $tablePlaylistTracks pt
        WHERE pt.playlist_id = p.id
        ORDER BY pt.added_at ASC, pt.rowid ASC
        LIMIT 1
      ) END AS preview_track_json''',
      alias: 'p',
    );
    final playlistTrackRows = <Map<String, dynamic>>[];
    Object? lastId;
    int? lastRowId;
    while (true) {
      final page = await txn.rawQuery('''
        SELECT rowid AS __collection_rowid, playlist_id, track_key
        FROM $tablePlaylistTracks
        ${lastRowId == null ? '' : 'WHERE playlist_id>? OR (playlist_id=? AND rowid>?)'}
        ORDER BY playlist_id ASC,rowid ASC LIMIT 256
      ''', lastRowId == null ? const [] : [lastId, lastId, lastRowId]);
      if (page.isEmpty) break;
      lastId = page.last['playlist_id'];
      lastRowId = page.last['__collection_rowid'] as int;
      playlistTrackRows.addAll(page.map(_withoutRowCursor));
      if (page.length < 256) break;
    }
    final favoriteArtistRows = await _readDateOrderedRows(
      txn,
      tableFavoriteArtists,
      'added_at',
    );
    return LibraryCollectionsSnapshot(
      lovedRows: lovedRows,
      playlistRows: playlistRows,
      playlistTrackRows: playlistTrackRows,
      favoriteArtistRows: favoriteArtistRows,
    );
  });
}

Future<LibraryPlaylistTracksSnapshot> readDartPlaylistTracks(
  Database db,
  String playlistId,
) async {
  final rows = await db.transaction(
    (txn) => _readDateOrderedRows(
      txn,
      tablePlaylistTracks,
      'added_at',
      ascending: true,
      where: 'playlist_id=?',
      whereArgs: [playlistId],
    ),
  );
  return LibraryPlaylistTracksSnapshot(rows: rows);
}

Map<String, dynamic> _withoutRowCursor(Map<String, Object?> row) =>
    Map<String, dynamic>.from(row)..remove('__collection_rowid');

Future<List<Map<String, dynamic>>> _readDateOrderedRows(
  DatabaseExecutor db,
  String table,
  String dateColumn, {
  bool ascending = false,
  String projection = '*',
  String? alias,
  String? where,
  List<Object?> whereArgs = const [],
}) async {
  final rows = <Map<String, dynamic>>[];
  final qualifier = alias == null ? '' : '$alias.';
  final comparison = ascending ? '>' : '<';
  final direction = ascending ? 'ASC' : 'DESC';
  Object? lastDate;
  int? lastRowId;
  while (true) {
    final predicates = [
      if (where != null) '($where)',
      if (lastRowId != null)
        '($qualifier$dateColumn$comparison? OR ($qualifier$dateColumn=? AND ${qualifier}rowid$comparison?))',
    ];
    final page = await db.rawQuery(
      '''
      SELECT ${qualifier}rowid AS __collection_rowid, $projection
      FROM $table ${alias ?? ''}
      ${predicates.isEmpty ? '' : 'WHERE ${predicates.join(' AND ')}'}
      ORDER BY $qualifier$dateColumn $direction,${qualifier}rowid $direction LIMIT 256
    ''',
      [
        ...whereArgs,
        if (lastRowId != null) ...[lastDate, lastDate, lastRowId],
      ],
    );
    if (page.isEmpty) break;
    lastDate = page.last[dateColumn];
    lastRowId = page.last['__collection_rowid'] as int;
    rows.addAll(page.map(_withoutRowCursor));
    if (page.length < 256) break;
  }
  return rows;
}

Future<LibraryCollectionsSnapshot> readNativeRows(
  Database db, {
  String? playlistId,
  NativeCollectionsJobRunner? nativeJobRunner,
  Directory? temporaryDirectory,
}) async {
  final temporary = await (temporaryDirectory ?? await getTemporaryDirectory())
      .createTemp('collection-read-');
  final path = '${temporary.path}/rows.ndjson';
  try {
    final snapshotPath = '${temporary.path}/$dbFileName';
    await _projectCollectionReadDatabase(
      db,
      snapshotPath,
      playlistId: playlistId,
    );
    final request = <String, dynamic>{
      'operation': 'collections_snapshot',
      'collections_path': snapshotPath,
      'output_path': path,
      'playlist_id': ?playlistId,
    };
    final result = await (nativeJobRunner ?? NativeDataJobs.run)(request);
    final counts = result['counts'];
    if (result['published'] != true ||
        result['rows_path'] != path ||
        counts is! Map) {
      throw const FormatException('Invalid native collection snapshot');
    }
    var total = 0;
    for (final count in counts.values) {
      if (count is! int || count < 0) {
        throw const FormatException('Invalid native collection row count');
      }
      total += count;
    }
    return LibraryCollectionsSnapshot(
      lovedRows: const [],
      playlistRows: const [],
      playlistTrackRows: const [],
      favoriteArtistRows: const [],
      nativeRowsPath: path,
      nativeRowsDirectory: temporary.path,
      nativeRowCount: total,
    );
  } on NativeSqliteSnapshotDetachException {
    _log.w('Retaining collection read staging after a failed database detach');
    rethrow;
  } catch (_) {
    await temporary.delete(recursive: true);
    rethrow;
  }
}

final _collectionProjectionQueue = Expando<Future<void>>();
var _collectionProjectionSequence = 0;

/// Both the live database and this projection are owned by the same SQLite
/// engine during copying. DETACH closes its private file before Rust opens
/// it; independent SQLite copies must never share a live app database.
Future<void> _projectCollectionReadDatabase(
  Database db,
  String outputPath, {
  String? playlistId,
}) async {
  final previous = _collectionProjectionQueue[db];
  final finished = Completer<void>();
  _collectionProjectionQueue[db] = finished.future;
  if (previous != null) await previous;
  final alias = 'collection_read_${_collectionProjectionSequence++}';
  var attached = false;
  try {
    await db.execute('ATTACH DATABASE ? AS $alias', [outputPath]);
    attached = true;
    await db.transaction((txn) async {
      for (final table in [
        tableLoved,
        tableFavoriteArtists,
        tablePlaylists,
        tablePlaylistTracks,
      ]) {
        final where = playlistId == null
            ? ''
            : table == tablePlaylists
            ? 'WHERE id=?'
            : table == tablePlaylistTracks
            ? 'WHERE playlist_id=?'
            : 'WHERE 0';
        // CTAS copies every original column and value. Inserting in original
        // rowid order preserves all date-tie and membership ordering without
        // transferring any collection rows through the platform channel.
        await txn.execute(
          'CREATE TABLE $alias.$table AS '
          'SELECT * FROM main.$table $where ORDER BY rowid ASC',
          where.contains('?') ? [playlistId] : const [],
        );
      }
      await txn.execute('PRAGMA $alias.user_version=$dbVersion');
      await txn.execute(
        'CREATE INDEX $alias.collection_read_members '
        'ON $tablePlaylistTracks(playlist_id)',
      );
      await txn.execute(
        'CREATE INDEX $alias.collection_read_preview '
        'ON $tablePlaylistTracks(playlist_id,added_at)',
      );
    });
  } finally {
    try {
      if (attached) {
        await detachNativeSqliteSnapshot(db, alias, outputPath);
      }
    } finally {
      finished.complete();
    }
  }
}
