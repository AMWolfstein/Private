import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/sqlite_helpers.dart';
import 'package:sistrum/utils/logger.dart';
import 'support/sqlite_process_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final prefix in ['', 'private_scan.']) {
    test('rescans retain old collection IDs and path keys ($prefix)', () async {
      final db = await SqliteProcessDatabase.open();
      addTearDown(db.close);
      await db.execute(
        'CREATE TABLE library(id TEXT PRIMARY KEY,file_path TEXT,source_id TEXT)',
      );
      await db.execute(
        "INSERT INTO library VALUES('lib_legacy','/music/Aa.flac','source')",
      );
      if (prefix.isNotEmpty) {
        await db.execute("ATTACH DATABASE ':memory:' AS private_scan");
      }
      final table = '${prefix}scan';
      final keys = '${prefix}scan_keys';
      await db.execute(
        'CREATE TABLE $table(id TEXT PRIMARY KEY,file_path TEXT)',
      );
      await db.execute(
        'CREATE TABLE $keys(item_id TEXT,path_key TEXT,PRIMARY KEY(item_id,path_key))',
      );
      await db.execute(
        "INSERT INTO $table VALUES('lib_v2_first','/music/Aa.flac'),('lib_v2_second','/music/B@.flac')",
      );
      await db.execute(
        "INSERT INTO $keys VALUES('lib_v2_first','/music/Aa.flac'),('lib_v2_second','/music/B@.flac')",
      );
      await preserveLibraryScanIds(
        db,
        sourceId: 'source',
        stageTable: table,
        keysTable: keys,
      );
      expect(await db.rawQuery('SELECT id FROM $table ORDER BY id'), [
        {'id': 'lib_legacy'},
        {'id': 'lib_v2_second'},
      ]);
      expect(
        await db.rawQuery(
          "SELECT path_key FROM $keys WHERE item_id='lib_legacy'",
        ),
        [
          {'path_key': '/music/Aa.flac'},
        ],
      );
      expect(
        await db.rawQuery("SELECT * FROM $keys WHERE item_id='lib_v2_first'"),
        isEmpty,
      );
      final old = await preserveLibraryRowId(db, {
        'id': 'lib_v2_first',
        'file_path': '/music/Aa.flac',
        'source_id': 'source',
      });
      expect(old['id'], 'lib_legacy');
      final other = await preserveLibraryRowId(db, {
        'id': 'lib_v2_first',
        'file_path': '/music/Aa.flac',
        'source_id': 'other',
      });
      expect(other['id'], 'lib_v2_first');
    });
  }
  test('shared log exports disclose their retained local path information', () {
    expect(logExportPrivacyNotice, contains('content URIs'));
  });
}
