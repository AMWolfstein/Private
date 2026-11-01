import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/library/collections/collection_browser_reader.dart';
import '../../../support/sqlite_process_database.dart';

void main() {
  late Directory root;
  late SqliteProcessDatabase database;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('car-collections-');
    database = await SqliteProcessDatabase.open(
      path: '${root.path}/collections.db',
    );
    await database.execute(
      'CREATE TABLE playlists(id TEXT PRIMARY KEY,name TEXT,cover_image_path TEXT,created_at TEXT)',
    );
    await database.execute(
      'CREATE TABLE playlist_tracks(playlist_id TEXT,track_key TEXT,track_json TEXT,added_at TEXT)',
    );
    await database.execute(
      'CREATE TABLE loved_tracks(track_key TEXT,track_json TEXT,added_at TEXT)',
    );
    await database.execute(
      "INSERT INTO playlists VALUES ('p','Beyoncé road trip','/local/cover.jpg','2026'),('empty','Empty',NULL,'2027')",
    );
    await database.execute(
      '''WITH RECURSIVE seq(n) AS (VALUES(0) UNION ALL SELECT n+1 FROM seq WHERE n<1002)
      INSERT INTO playlist_tracks SELECT 'p',printf('key%d',n),json_object('id',printf('t%d',n),'name',printf('Track %d',n),'artistName','Artist','albumName','Album','duration',60), '2026' FROM seq''',
    );
  });
  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });
  test(
    'playlist pages preserve order beyond 500 and avoid hydrating the library',
    () async {
      final reader = CollectionBrowserReader(database);
      final summaries = await reader.playlists();
      expect(summaries.length, 1);
      expect(summaries.single.count, 1003);
      expect(summaries.single.cover, '/local/cover.jpg');
      final middle = await reader.tracks(
        playlistId: 'p',
        offset: 500,
        limit: 500,
      );
      expect(middle.tracks.first.id, 't500');
      expect(middle.tracks.last.id, 't999');
      expect(middle.hasMore, true);
      final last = await reader.tracks(
        playlistId: 'p',
        offset: 1000,
        limit: 500,
      );
      expect(last.tracks.map((t) => t.id), ['t1000', 't1001', 't1002']);
      expect(last.hasMore, false);
    },
  );
  test(
    'search uses the existing Unicode normalizer and binds arbitrary text safely',
    () async {
      final reader = CollectionBrowserReader(database);
      expect((await reader.playlists(search: 'BEYONCE\u0301')).single.id, 'p');
      expect(await reader.playlists(search: "' OR 1=1 --"), isEmpty);
      expect((await reader.tracks(playlistId: "p' OR 1=1 --")).tracks, isEmpty);
    },
  );
  test(
    'malformed rows do not make a raw page falsely report the end of a collection',
    () async {
      await database.execute(
        "UPDATE playlist_tracks SET track_json='broken' WHERE track_key='key500'",
      );
      final page = await CollectionBrowserReader(
        database,
      ).tracks(playlistId: 'p', offset: 500, limit: 500);
      expect(page.tracks.length, 499);
      expect(page.hasMore, true);
      expect(
        (await CollectionBrowserReader(
          database,
        ).tracks(playlistId: 'p', offset: 1000, limit: 500)).tracks.length,
        3,
      );
    },
  );
}
