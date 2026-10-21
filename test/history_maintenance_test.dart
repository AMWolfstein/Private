import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:spotiflac_android/services/history_maintenance.dart';

import 'support/sqlite_process_database.dart';

class _HistoryRows implements DatabaseExecutor {
  final statements = <Map<String, Object?>>[];
  final _keys = _PathKeys();

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    statements.add({
      'sql':
          'UPDATE $table SET ${values.keys.map((key) => '$key = ?').join(', ')} WHERE $where',
      'args': [...values.values, ...?whereArgs],
    });
    return whereArgs!.single == 'kept' ? 1 : 0;
  }

  @override
  Batch batch() => _keys;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PathKeys implements Batch {
  final statements = <Map<String, Object?>>[];

  @override
  void delete(String table, {String? where, List<Object?>? whereArgs}) {
    statements.add({
      'sql': 'DELETE FROM $table WHERE $where',
      'args': whereArgs,
    });
  }

  @override
  void insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    expect(conflictAlgorithm, ConflictAlgorithm.ignore);
    statements.add({
      'sql':
          'INSERT OR IGNORE INTO $table (${values.keys.join(', ')}) VALUES (${values.keys.map((_) => '?').join(', ')})',
      'args': values.values.toList(),
    });
  }

  @override
  Future<List<Object?>> commit({
    bool? exclusive,
    bool? noResult,
    bool? continueOnError,
  }) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('atomic streaming restore rolls back a late stream failure', () async {
    final db = await SqliteProcessDatabase.open();
    addTearDown(db.close);
    await db.execute(
      'CREATE TABLE history(id TEXT PRIMARY KEY, file_path TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE history_path_keys(item_id TEXT, path_key TEXT, '
      'PRIMARY KEY(item_id, path_key))',
    );
    await db.insert('history', {
      'id': 'previous',
      'file_path': '/music/old.flac',
    });
    await db.insert('history_path_keys', {
      'item_id': 'previous',
      'path_key': 'old-key',
    });
    Stream<Map<String, dynamic>> brokenBackup() async* {
      for (var i = 0; i < 501; i++) {
        yield {'id': '$i', 'file_path': '/music/$i.flac'};
      }
      throw const FormatException('truncated backup');
    }

    await expectLater(
      replaceHistoryRows(db, brokenBackup()),
      throwsFormatException,
    );
    expect(await db.query('history'), [
      {'id': 'previous', 'file_path': '/music/old.flac'},
    ]);
    expect(await db.query('history_path_keys'), [
      {'item_id': 'previous', 'path_key': 'old-key'},
    ]);
    await replaceHistoryRows(
      db,
      Stream.fromIterable([
        {'id': 'restored', 'file_path': '/music/restored.flac'},
      ]),
    );
    expect(await db.query('history'), [
      {'id': 'restored', 'file_path': '/music/restored.flac'},
    ]);
    final keys = await db.query('history_path_keys');
    expect(keys, isNotEmpty);
    expect(keys.every((row) => row['item_id'] == 'restored'), isTrue);
  });

  test(
    'late maintenance cannot recreate deleted rows or their path keys',
    () async {
      final db = _HistoryRows();
      final updated = await updateExistingHistoryRows(db, [
        {
          'id': 'removed',
          'file_path': '/music/removed.flac',
          'quality': '24-bit',
        },
        {'id': 'kept', 'file_path': '/music/kept.opus', 'quality': 'Opus'},
      ]);
      expect(updated, {'kept'});
      final result = await Process.run('python3', [
        '-c',
        r'''
import json, sqlite3, sys
db = sqlite3.connect(':memory:')
db.executescript("""
CREATE TABLE history(id TEXT PRIMARY KEY, file_path TEXT, quality TEXT);
CREATE TABLE history_path_keys(item_id TEXT, path_key TEXT, UNIQUE(item_id,path_key));
INSERT INTO history VALUES ('removed','/music/removed.flac','16-bit'),('kept','/music/kept.flac','16-bit');
INSERT INTO history_path_keys SELECT id,file_path FROM history;
DELETE FROM history WHERE id='removed';
DELETE FROM history_path_keys WHERE item_id='removed';
""")
with db:
    for statement in json.loads(sys.argv[1]):
        db.execute(statement['sql'], statement['args'])
print(json.dumps({
  'rows': list(db.execute('SELECT id,file_path,quality FROM history')),
  'keys': list(db.execute('SELECT item_id,path_key FROM history_path_keys'))
}))
''',
        jsonEncode([...db.statements, ...db._keys.statements]),
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(data['rows'], [
        ['kept', '/music/kept.opus', 'Opus'],
      ]);
      expect(
        (data['keys'] as List).every((row) => (row as List).first == 'kept'),
        isTrue,
      );
      expect(data['keys'], isNotEmpty);
    },
  );
}
