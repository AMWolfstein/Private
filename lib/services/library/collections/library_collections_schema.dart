import 'package:sqflite/sqflite.dart';
import 'package:sistrum/utils/logging/logger.dart';

final _log = AppLogger('LibraryCollectionsDb');

const dbFileName = 'library_collections.db';
const dbVersion = 4;

const tableLoved = 'loved_tracks';
const tablePlaylists = 'playlists';
const tablePlaylistTracks = 'playlist_tracks';
const tableFavoriteArtists = 'favorite_artists';

Future<void> createCollectionsSchema(Database db, int version) async {
  _log.i('Creating collections database schema v$version');

  await db.execute('''
    CREATE TABLE $tableLoved (
      track_key TEXT PRIMARY KEY,
      track_json TEXT NOT NULL,
      added_at TEXT NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE $tablePlaylists (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      cover_image_path TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE $tablePlaylistTracks (
      playlist_id TEXT NOT NULL,
      track_key TEXT NOT NULL,
      track_json TEXT NOT NULL,
      added_at TEXT NOT NULL,
      PRIMARY KEY (playlist_id, track_key),
      FOREIGN KEY (playlist_id) REFERENCES $tablePlaylists(id) ON DELETE CASCADE
    )
  ''');

  await _createFavoriteArtistsTable(db);

  await db.execute(
    'CREATE INDEX idx_${tableLoved}_added_at ON $tableLoved(added_at DESC)',
  );
  await db.execute(
    'CREATE INDEX idx_${tablePlaylists}_created_at ON $tablePlaylists(created_at DESC)',
  );
  await db.execute(
    'CREATE INDEX idx_${tablePlaylistTracks}_playlist_id ON $tablePlaylistTracks(playlist_id)',
  );
  await db.execute(
    'CREATE INDEX idx_${tablePlaylistTracks}_added_at ON $tablePlaylistTracks(added_at DESC)',
  );
  // OPT-PERF-003: the playlist picker filters memberships by track_key.
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_${tablePlaylistTracks}_track_key ON $tablePlaylistTracks(track_key, playlist_id)',
  );
}

Future<void> _createFavoriteArtistsTable(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS $tableFavoriteArtists (
      artist_key TEXT PRIMARY KEY,
      artist_json TEXT NOT NULL,
      added_at TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_${tableFavoriteArtists}_added_at ON $tableFavoriteArtists(added_at DESC)',
  );
}
