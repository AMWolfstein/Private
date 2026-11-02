import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sistrum/services/library/covers/library_cover_snapshot.dart';
import 'package:sistrum/services/library/covers/publish_scanned_covers.dart';

void main() {
  late Database db;
  late Directory directory;
  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE library (source_id TEXT, cover_path TEXT)');
    directory = await Directory.systemTemp.createTemp('sistrum-cover-publish-');
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<File> staged(List<int> data) async {
    final folder = await Directory('${directory.path}/full_scan_next').create();
    return File('${folder.path}/stable.jpg').writeAsBytes(data);
  }

  test(
    'successful publication keeps a stable cover path across generations',
    () async {
      final old = await File('${directory.path}/stable.jpg').writeAsBytes([1]);
      final fresh = await staged([2, 3]);
      await db.insert('library', {'source_id': 's', 'cover_path': fresh.path});
      expect(
        await stabilizePublishedLibraryCovers(
          db,
          's',
          directory,
          canPublish: () => true,
        ),
        1,
      );
      expect((await db.query('library')).single['cover_path'], old.path);
      expect(await old.readAsBytes(), [2, 3]);
      expect(await fresh.exists(), isTrue);
    },
  );

  test(
    'cancellation preserves the old thumbnail and committed staged path',
    () async {
      final old = await File('${directory.path}/stable.jpg').writeAsBytes([1]);
      final fresh = await staged([2]);
      await db.insert('library', {'source_id': 's', 'cover_path': fresh.path});
      var checks = 0;
      await stabilizePublishedLibraryCovers(
        db,
        's',
        directory,
        canPublish: () => ++checks < 3,
      );
      expect(await old.readAsBytes(), [1]);
      expect((await db.query('library')).single['cover_path'], fresh.path);
      expect(
        await directory
            .list()
            .where((f) => f.path.contains('.publish-'))
            .isEmpty,
        isTrue,
      );
    },
  );

  test(
    'cross-store references include long JSON and rebase old container paths',
    () async {
      await db.execute('CREATE TABLE copied (value TEXT)');
      final value = jsonEncode({
        'padding': 'x' * 600000,
        'art': 'file:///old/container/library_covers/full_scan_old/kept.jpg',
      });
      await db.insert('copied', {'value': value});
      final paths = await readStoredLibraryCoverPaths(directory, [
        (database: db, table: 'copied', column: 'value'),
      ]);
      expect(paths, {'${directory.path}/full_scan_old/kept.jpg'});
      await expectLater(
        readStoredLibraryCoverPaths(directory, [
          (database: db, table: 'missing', column: 'value'),
        ]),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test('native projection includes externally referenced covers', () async {
    final kept = '${directory.path}/external.jpg';
    await db.insert('library', {
      'source_id': 's',
      'cover_path': '${directory.path}/library.jpg',
    });
    final count = await withLibraryCoverSnapshot(db, (path) async {
      final snapshot = await databaseFactoryFfi.openDatabase(path);
      try {
        final rows = await snapshot.query('library');
        expect(rows.map((r) => r['cover_path']), contains(kept));
        return rows.length;
      } finally {
        await snapshot.close();
      }
    }, storedReferences: {kept});
    expect(count, 2);
  });
  test(
    'copied-reference writers wait until maintenance releases their barrier',
    () async {
      await db.execute('CREATE TABLE copied (value TEXT)');
      final entered = Completer<void>(), release = Completer<void>();
      final maintenance = withCoverReferenceBarriers(
        [(database: db, table: 'copied', column: 'value')],
        (columns) async {
          expect(columns.single.database, isA<Transaction>());
          entered.complete();
          await release.future;
        },
      );
      await entered.future;
      var written = false;
      final writing = db
          .insert('copied', {'value': 'cover'})
          .then((_) => written = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(written, isFalse);
      release.complete();
      await maintenance;
      await writing;
      expect(written, isTrue);
    },
  );
}
