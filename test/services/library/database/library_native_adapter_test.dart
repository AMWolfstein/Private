import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/native/library_scan_bridge.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sistrum/services/library/database/library_native_adapter.dart';
import 'package:sistrum/services/library/database/library_row_mapper.dart';
import 'package:sistrum/services/library/database/sqlite_native_snapshot.dart';

import '../../../support/library_native_fixture.dart';
import '../../../support/sqlite_process_database.dart';

part 'library_native_adapter_staging.dart';
part 'library_native_adapter_timestamps.dart';

class _NativeHarness {
  _NativeHarness(this.live);
  final Database live;
  List<Map<String, dynamic>> incremental = [];
  List<String> removed = [];
  Future<void> Function()? afterStage;
  final stagedPaths = <String>[];

  Future<Map<String, dynamic>> run(
    Map<String, dynamic> request, {
    String? requestId,
  }) async {
    final path = request['library_path'] as String;
    expect(path, isNot(live.path));
    expect(
      (await live.rawQuery('PRAGMA database_list')).map((r) => r['file']),
      isNot(contains(path)),
    );
    stagedPaths.add(path);
    final private = await SqliteProcessDatabase.open(path: path);
    final snapshot = request['operation'] == 'library_snapshot';
    var count = 0;
    try {
      if (snapshot) {
        final indexes = await private.rawQuery('PRAGMA index_list(library)');
        expect(
          indexes.any((row) => row['name'] == 'native_library_snapshot_id'),
          isTrue,
        );
        final rows = await private.query('library', orderBy: 'id');
        final lines = <String>[];
        for (final row in rows) {
          var timestamp =
              (row['audio_metadata_scan_version'] as num).toInt() < 4
              ? -1
              : (row['file_mod_time'] as num?)?.toInt() ?? 0;
          if (timestamp == 0) {
            timestamp = 999;
            await private.update(
              'library',
              {'file_mod_time': timestamp, 'sort_added': timestamp},
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          }
          lines.add('$timestamp\t${row['file_path']}');
        }
        await File(
          request['snapshot_path'] as String,
        ).writeAsString('${lines.join('\n')}\n');
        count = rows.length;
      } else {
        expect(await private.query('library'), isEmpty);
        expect(request, isNot(contains('history_path')));
        final full = request['operation'] == 'library_full_import';
        final rows = full
            ? (await File(request['ndjson_path'] as String).readAsLines())
                  .where((line) => line.isNotEmpty)
                  .map(
                    (line) =>
                        Map<String, dynamic>.from(jsonDecode(line) as Map),
                  )
                  .toList()
            : incremental;
        for (final row in rows) {
          await addNativeLibraryTrack(private, row);
        }
        count = rows.length;
        if (!full) {
          expect(request['retain_removed_paths'], isTrue);
          await private.execute(
            'CREATE TABLE native_library_removed_paths(ordinal INTEGER PRIMARY KEY,path TEXT NOT NULL)',
          );
          for (var i = 0; i < removed.length; i++) {
            await private.execute(
              'INSERT INTO native_library_removed_paths VALUES(?,?)',
              [i, removed[i]],
            );
          }
        }
      }
    } finally {
      await private.close();
    }
    await afterStage?.call();
    return {
      'committed': true,
      'inserted': count,
      'scanned_count': count,
      'totalFiles': count + 3,
      'skippedCount': 3,
      if (snapshot) 'path': request['snapshot_path'],
    };
  }
}

class _SqlProbe implements Database, Transaction {
  _SqlProbe(this.inner, this.path, this.onSql);
  final DatabaseExecutor inner;
  @override
  final String path;
  final void Function(String) onSql;
  @override
  Future<void> execute(String sql, [List<Object?>? args]) async {
    if (sql.startsWith('DETACH')) onSql(sql);
    await inner.execute(sql, args);
    if (!sql.startsWith('DETACH')) onSql(sql);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? args,
  ]) => inner.rawQuery(sql, args);
  @override
  Future<int> rawDelete(String sql, [List<Object?>? args]) async {
    final result = await inner.rawDelete(sql, args);
    onSql(sql);
    return result;
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? args]) async {
    final result = await inner.rawUpdate(sql, args);
    onSql(sql);
    return result;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => inner.query(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
  );
  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction) action, {
    bool? exclusive,
  }) => (inner as Database).transaction(
    (txn) => action(_SqlProbe(txn, path, onSql)),
    exclusive: exclusive,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  _registerLibraryNativeAdapterStaging();
  _registerLibraryNativeAdapterTimestamps();
}
