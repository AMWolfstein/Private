import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sistrum/services/library/sqlite_helpers.dart';

class _RecordingExecutor extends Fake implements DatabaseExecutor {
  final statements = <String>[];
  final inserts = <String>[];

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    statements.add(sql.trim());
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    statements.add(sql.trim());
    return const [];
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async {
    inserts.add(sql.trim());
    return 1;
  }
}

class _FailingIndexExecutor extends _RecordingExecutor {
  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    if (sql.contains('CREATE VIRTUAL TABLE IF NOT EXISTS')) {
      throw Exception('disk I/O error');
    }
    await super.execute(sql, arguments);
  }
}

void main() {
  group('SingleFlightInitializer', () {
    test('coalesces concurrent initialization and caches the result', () async {
      final initializer = SingleFlightInitializer<int>();
      final gate = Completer<void>();
      var calls = 0;

      Future<int> create() async {
        calls++;
        await gate.future;
        return 42;
      }

      final first = initializer.getOrCreate(create);
      final second = initializer.getOrCreate(create);

      expect(identical(first, second), isTrue);
      expect(calls, 1);

      gate.complete();
      expect(await Future.wait([first, second]), [42, 42]);
      expect(await initializer.getOrCreate(create), 42);
      expect(calls, 1);
    });

    test('allows retry after initialization fails', () async {
      final initializer = SingleFlightInitializer<int>();
      var calls = 0;

      Future<int> create() {
        calls++;
        if (calls == 1) throw StateError('first attempt failed');
        return Future<int>.value(7);
      }

      await expectLater(initializer.getOrCreate(create), throwsStateError);
      expect(await initializer.getOrCreate(create), 7);
      expect(calls, 2);
    });

    test('reset permits a fresh initialization', () async {
      final initializer = SingleFlightInitializer<int>();
      var value = 1;

      expect(await initializer.getOrCreate(() async => value), 1);
      value = 2;
      expect(await initializer.getOrCreate(() async => value), 1);

      initializer.reset();
      expect(await initializer.getOrCreate(() async => value), 2);
    });
  });

  group('SQLite startup configuration', () {
    late Directory documents;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      documents = Directory.systemTemp.createTempSync('sistrum-sqlite-test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => call.method == 'getApplicationDocumentsDirectory'
                ? documents.path
                : null,
          );
    });

    tearDownAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      documents.deleteSync(recursive: true);
    });

    Future<void> createTable(Database db, int version) => db.execute(
      'CREATE TABLE tracks (id INTEGER PRIMARY KEY, search_text TEXT)',
    );

    Future<Object?> pragma(Database db, String name) async {
      final rows = await db.rawQuery('PRAGMA $name');
      return rows.single.values.single;
    }

    test('a fresh database gets the startup pragmas', () async {
      final db = await openAppDatabase(
        'fresh.db',
        version: 1,
        onCreate: createTable,
        onUpgrade: (_, _, _) async {},
      );
      addTearDown(db.close);

      expect(await pragma(db, 'busy_timeout'), 5000);
      expect(await pragma(db, 'journal_mode'), 'wal');
      expect(await pragma(db, 'synchronous'), 1);
      expect(await pragma(db, 'recursive_triggers'), 1);
      expect(await pragma(db, 'auto_vacuum'), 2);
      expect(await pragma(db, 'foreign_keys'), 0);
    });

    test('an existing schema keeps auto-vacuum and follows foreign keys', () async {
      final first = await openAppDatabase(
        'existing.db',
        version: 1,
        onCreate: createTable,
        onUpgrade: (_, _, _) async {},
        incrementalAutoVacuum: false,
      );
      expect(await pragma(first, 'auto_vacuum'), 0);
      await first.close();

      final reopened = await openAppDatabase(
        'existing.db',
        version: 1,
        onCreate: createTable,
        onUpgrade: (_, _, _) async {},
        foreignKeys: true,
      );
      addTearDown(reopened.close);

      expect(await pragma(reopened, 'auto_vacuum'), 0);
      expect(await pragma(reopened, 'foreign_keys'), 1);
      expect(await pragma(reopened, 'journal_mode'), 'wal');
    });
  });

  group('FTS5 search query', () {
    test(
      'quotes literal input and leaves unsupported short terms to fallback',
      () {
        expect(ftsPhraseSearchQuery('ab'), isNull);
        expect(ftsPhraseSearchQuery('beat'), '"beat"');
        expect(ftsPhraseSearchQuery('foo"bar'), '"foo""bar"');
        expect(ftsPhraseSearchQuery('a\u0000b'), isNull);
      },
    );

    test('recognizes missing FTS5 and trigram capability errors', () {
      expect(
        isTrigramFts5UnavailableError(
          Exception('DatabaseException(no such module: fts5)'),
        ),
        isTrue,
      );
      expect(
        isTrigramFts5UnavailableError(
          Exception('DatabaseException(no such tokenizer: trigram)'),
        ),
        isTrue,
      );
      expect(
        isTrigramFts5UnavailableError(Exception('database is locked')),
        isFalse,
      );
    });
  });

  group('trigram FTS5 index', () {
    test('probes the runtime, builds the index and drops its probe table', () async {
      final db = _RecordingExecutor();

      final created = await createTrigramFtsIndex(
        db,
        ftsTable: 'library_fts',
        contentTable: 'library',
        triggerPrefix: 'library_fts',
      );

      expect(created, isTrue);
      expect(
        db.statements.any(
          (sql) =>
              sql.contains('CREATE VIRTUAL TABLE temp.') &&
              sql.contains("tokenize='trigram'"),
        ),
        isTrue,
      );
      expect(
        db.statements.any((sql) => sql.contains('DROP TABLE IF EXISTS temp.')),
        isTrue,
      );
      expect(
        db.statements.where((sql) => sql.startsWith('CREATE TRIGGER')).length,
        3,
      );
      expect(db.inserts.single, contains('VALUES (?)'));
      expect(db.inserts.single, contains('library_fts'));
    });

    test('a failed index creation removes every partial object', () async {
      final db = _FailingIndexExecutor();

      final created = await createTrigramFtsIndex(
        db,
        ftsTable: 'library_fts',
        contentTable: 'library',
        triggerPrefix: 'library_fts',
      );

      expect(created, isFalse);
      expect(
        db.statements.where((sql) => sql.startsWith('DROP TRIGGER IF EXISTS')).length,
        3,
      );
      expect(
        db.statements.any(
          (sql) => sql == 'DROP TABLE IF EXISTS library_fts',
        ),
        isTrue,
      );
    });
  });
}
