import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/library/library_collections_read.dart';
import 'package:sistrum/services/library/library_collections_schema.dart';

import 'support/sqlite_process_database.dart';

const _lovedJson = '{"id":"a","name":"Loved song","artistName":"Artist"}';
const _previewJson = '{"id":"p1","name":"First track","artistName":"Artist"}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SqliteProcessDatabase db;

  setUp(() async {
    db = await SqliteProcessDatabase.open();
    await createCollectionsSchema(db, dbVersion);
    await db.insert(tableLoved, {
      'track_key': 'loved-a',
      'track_json': _lovedJson,
      'added_at': '2026-01-02T00:00:00.000Z',
    });
    // Playlist "p1" has no cover, so its preview is its first track.
    await db.insert(tablePlaylists, {
      'id': 'p1',
      'name': 'Road',
      'cover_image_path': null,
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    });
    await db.insert(tablePlaylistTracks, {
      'playlist_id': 'p1',
      'track_key': 'track-1',
      'track_json': _previewJson,
      'added_at': '2026-01-01T01:00:00.000Z',
    });
    await db.insert(tablePlaylistTracks, {
      'playlist_id': 'p1',
      'track_key': 'track-2',
      'track_json': _lovedJson,
      'added_at': '2026-01-01T02:00:00.000Z',
    });
    await db.insert(tableFavoriteArtists, {
      'artist_key': 'artist',
      'artist_json': '{"name":"Artist"}',
      'added_at': '2026-01-03T00:00:00.000Z',
    });
  });

  tearDown(() => db.close());

  test('the snapshot holds loved songs, playlists, members and artists', () async {
    final snapshot = await readDartSnapshot(db);
    expect(snapshot.lovedRows.map((row) => row['track_key']), ['loved-a']);
    expect(snapshot.playlistRows.map((row) => row['id']), ['p1']);
    expect(
      snapshot.playlistTrackRows.map((row) => row['track_key']),
      ['track-1', 'track-2'],
    );
    expect(snapshot.favoriteArtistRows.map((row) => row['artist_key']), [
      'artist',
    ]);
  });

  test('a playlist without a cover gets its first track as the preview', () async {
    final snapshot = await readDartSnapshot(db);
    final playlist = snapshot.playlistRows.single;
    expect(playlist['preview_track_json'], _previewJson);
  });

  test('a playlist with a cover has no preview track', () async {
    await db.update(
      tablePlaylists,
      {'cover_image_path': '/covers/p1.jpg'},
      where: 'id = ?',
      whereArgs: ['p1'],
    );
    final playlist = (await readDartSnapshot(db)).playlistRows.single;
    expect(playlist['preview_track_json'], isNull);
  });

  test('reading one playlist returns only its members, oldest first', () async {
    await db.insert(tablePlaylists, {
      'id': 'p2',
      'name': 'Other',
      'cover_image_path': null,
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    });
    await db.insert(tablePlaylistTracks, {
      'playlist_id': 'p2',
      'track_key': 'other-track',
      'track_json': _lovedJson,
      'added_at': '2026-01-01T00:30:00.000Z',
    });

    final snapshot = await readDartPlaylistTracks(db, 'p1');
    expect(snapshot.rows.map((row) => row['track_key']), [
      'track-1',
      'track-2',
    ]);
  });
}
