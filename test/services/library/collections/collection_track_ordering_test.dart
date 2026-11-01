import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/library/collections/collection_track_ordering.dart';
import '../../../support/sqlite_process_database.dart';

void main() {
  late Directory root;
  late SqliteProcessDatabase db;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('collection-order-');
    db = await SqliteProcessDatabase.open(path: '${root.path}/c.db');
    await db.execute(
      'CREATE TABLE loved_tracks(track_key TEXT PRIMARY KEY, track_json TEXT, added_at TEXT)',
    );
    await db.execute(
      'CREATE TABLE playlist_tracks(playlist_id TEXT,track_key TEXT,track_json TEXT,added_at TEXT,PRIMARY KEY(playlist_id,track_key))',
    );
    await db.execute(
      'CREATE TABLE playlists(id TEXT PRIMARY KEY,updated_at TEXT)',
    );
    await db.execute("INSERT INTO playlists VALUES ('p','2026-01-01')");
    for (var i = 0; i < 260; i++) {
      await db.rawInsert('INSERT INTO loved_tracks VALUES (?,?,?)', [
        'k$i',
        'metadata$i',
        '2026-01-01T00:00:00.000Z',
      ]);
      await db.rawInsert('INSERT INTO playlist_tracks VALUES (?,?,?,?)', [
        'p',
        'k$i',
        'metadata$i',
        '2026-01-01T00:00:00.000Z',
      ]);
    }
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  test(
    'reorders across batch boundaries preserving metadata and both sort contracts',
    () async {
      final keys = List.generate(260, (i) => 'k${259 - i}');
      final ordering = CollectionTrackOrdering(db);
      await ordering.reorder(keys);
      await ordering.reorder(keys, playlistId: 'p');
      for (final table in ['loved_tracks', 'playlist_tracks']) {
        final rows = await db.rawQuery(
          'SELECT track_key,track_json FROM $table ORDER BY added_at ${table == 'loved_tracks' ? 'DESC' : 'ASC'}',
        );
        expect(rows.map((r) => r['track_key']), keys);
        expect(rows.first['track_json'], 'metadata259');
      }
      await db.rawInsert(
        "INSERT INTO loved_tracks VALUES ('new','new','2099-01-01')",
      );
      expect(
        (await db.rawQuery(
          'SELECT track_key FROM loved_tracks ORDER BY added_at DESC LIMIT 1',
        )).single['track_key'],
        'new',
      );
    },
  );
  test(
    'stale, duplicate and missing orders cannot partially change membership',
    () async {
      final ordering = CollectionTrackOrdering(db);
      final keys = List.generate(260, (i) => 'k$i');
      await expectLater(ordering.reorder([...keys, 'stale']), throwsStateError);
      await expectLater(ordering.reorder(['k0', 'k0']), throwsArgumentError);
      expect(
        (await db.rawQuery(
          'SELECT DISTINCT added_at FROM loved_tracks',
        )).length,
        1,
      );
      expect(
        (await db.rawQuery(
          'SELECT COUNT(*) AS n FROM loved_tracks',
        )).single['n'],
        260,
      );
    },
  );
}
