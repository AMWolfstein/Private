import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/models/library_collections.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/services/collection_restore_codec.dart';
import 'package:spotiflac_android/services/library_collections_database.dart';

import 'support/sqlite_process_database.dart';

void main() {
  for (final version in [1, 2]) {
    test('schema v$version upgrade preserves retained collections', () async {
      final db = await SqliteProcessDatabase.open();
      addTearDown(db.close);
      await db.execute('PRAGMA foreign_keys=ON');
      await db.execute(
        'CREATE TABLE wishlist_tracks(track_key TEXT PRIMARY KEY)',
      );
      await db.execute("INSERT INTO wishlist_tracks VALUES('obsolete')");
      await db.execute('CREATE TABLE loved_tracks(track_key TEXT PRIMARY KEY)');
      await db.execute("INSERT INTO loved_tracks VALUES('loved')");
      await db.execute('CREATE TABLE playlists(id TEXT PRIMARY KEY)');
      await db.execute("INSERT INTO playlists VALUES('playlist')");
      await db.execute(
        'CREATE TABLE playlist_tracks(playlist_id TEXT REFERENCES playlists(id),track_key TEXT)',
      );
      await db.execute("INSERT INTO playlist_tracks VALUES('playlist','song')");
      if (version == 2) {
        await db.execute(
          'CREATE TABLE favorite_artists(artist_key TEXT PRIMARY KEY,artist_json TEXT NOT NULL,added_at TEXT NOT NULL)',
        );
        await db.execute(
          "INSERT INTO favorite_artists VALUES('artist','{}','2026')",
        );
      }
      final tables = [
        'loved_tracks',
        'playlists',
        'playlist_tracks',
        if (version == 2) 'favorite_artists',
      ];
      final before = {
        for (final table in tables)
          table: await db.rawQuery('SELECT rowid,* FROM $table'),
      };
      await db.transaction(
        (_) => LibraryCollectionsDatabase.upgradeDatabaseSchema(db, version, 3),
      );
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE name='wishlist_tracks'",
        ),
        isEmpty,
      );
      for (final table in tables) {
        expect(await db.rawQuery('SELECT rowid,* FROM $table'), before[table]);
      }
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE name='favorite_artists'",
        ),
        hasLength(1),
      );
      await LibraryCollectionsDatabase.upgradeDatabaseSchema(db, version, 3);
    });
  }

  test('schema v4 adds the track_key membership index (OPT-PERF-003)', () async {
    final db = await SqliteProcessDatabase.open();
    addTearDown(db.close);
    await db.execute(
      'CREATE TABLE playlist_tracks(playlist_id TEXT NOT NULL,track_key TEXT NOT NULL,added_at TEXT NOT NULL,PRIMARY KEY(playlist_id,track_key))',
    );
    await LibraryCollectionsDatabase.upgradeDatabaseSchema(db, 3, 4);
    final plan = await db.rawQuery(
      'EXPLAIN QUERY PLAN SELECT playlist_id, COUNT(*) AS matched_count '
      'FROM playlist_tracks WHERE track_key IN (?, ?) GROUP BY playlist_id',
      ['a', 'b'],
    );
    final detail = plan.map((row) => row.values.join(' ')).join(' | ');
    expect(detail, contains('idx_playlist_tracks_track_key'));
  });

  test(
    'legacy JSON ignores removed data and exports retained collections only',
    () async {
      final entry = CollectionTrackEntry(
        key: 'local:song',
        track: const Track(
          id: 'song',
          name: 'Song',
          artistName: 'Artist',
          albumName: 'Album',
          duration: 180,
        ),
        addedAt: DateTime.utc(2026),
      ).toJson();
      final input = <String, dynamic>{
        'wishlist': [
          {'key': 7, 'track': false},
        ],
        'loved': [entry],
        'playlists': [
          {
            'id': 'playlist',
            'name': 'Playlist',
            'createdAt': '2026-01-01',
            'updatedAt': '2026-01-01',
            'tracks': [entry],
          },
        ],
        'favoriteArtists': <dynamic>[],
      };
      final state = LibraryCollectionsState.fromJson(input);
      expect(state.loved.single.track.id, 'song');
      expect(state.playlists.single.tracks.single.track.id, 'song');
      expect(state.toJson().keys, ['loved', 'playlists', 'favoriteArtists']);
      final commands = await prepareCollectionRestoreCommands(input, 'now');
      expect(commands.map((command) => command['kind']), [
        'loved',
        'playlist',
        'playlist_track',
      ]);
    },
  );
}
