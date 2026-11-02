import 'package:sqflite/sqflite.dart';
import 'package:sistrum/services/library/database/sqlite_helpers.dart'
    as sqlite;
import 'package:sistrum/services/playback/autoplay/song_analysis_store.dart'
    show SongFileStamp;

/// What the ReplayGain writer remembers between sessions: the file stamp each
/// track's tags were written for, and the fingerprint each album's gain was
/// measured from. A file or album that no longer matches is written again.
abstract interface class ReplayGainState {
  Future<SongFileStamp?> trackStamp(String path);
  Future<void> saveTrackStamp(String path, SongFileStamp stamp);
  Future<String?> albumFingerprint(String albumKey);
  Future<void> saveAlbumFingerprint(String albumKey, String fingerprint);
}

/// In-memory state, used by tests and when the database cannot be opened.
class MemoryReplayGainState implements ReplayGainState {
  final _tracks = <String, SongFileStamp>{};
  final _albums = <String, String>{};

  @override
  Future<SongFileStamp?> trackStamp(String path) async => _tracks[path];

  @override
  Future<void> saveTrackStamp(String path, SongFileStamp stamp) async =>
      _tracks[path] = stamp;

  @override
  Future<String?> albumFingerprint(String albumKey) async => _albums[albumKey];

  @override
  Future<void> saveAlbumFingerprint(String albumKey, String fingerprint) async =>
      _albums[albumKey] = fingerprint;
}

/// [ReplayGainState] in `replay_gain.db`, in the app's database folder.
class ReplayGainStateDb implements ReplayGainState {
  ReplayGainStateDb({Future<Database> Function()? open}) : _openDatabase = open;

  final Future<Database> Function()? _openDatabase;
  final _database = sqlite.SingleFlightInitializer<Database>();

  static const _schemaVersion = 1;

  Future<Database> _open() => _database.getOrCreate(
    _openDatabase ??
        () => sqlite.openAppDatabase(
          'replay_gain.db',
          version: _schemaVersion,
          onCreate: _create,
          onUpgrade: (db, oldVersion, newVersion) async {},
        ),
  );

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE track_stamps (
        path TEXT PRIMARY KEY NOT NULL,
        size INTEGER NOT NULL,
        modified INTEGER NOT NULL
      ) WITHOUT ROWID
    ''');
    await db.execute('''
      CREATE TABLE album_fingerprints (
        album_key TEXT PRIMARY KEY NOT NULL,
        fingerprint TEXT NOT NULL
      ) WITHOUT ROWID
    ''');
  }

  @override
  Future<SongFileStamp?> trackStamp(String path) async {
    final rows = await (await _open()).query(
      'track_stamps',
      columns: ['size', 'modified'],
      where: 'path = ?',
      whereArgs: [path],
    );
    if (rows.isEmpty) return null;
    return (
      size: rows.first['size']! as int,
      modified: rows.first['modified']! as int,
    );
  }

  @override
  Future<void> saveTrackStamp(String path, SongFileStamp stamp) async {
    await (await _open()).insert('track_stamps', {
      'path': path,
      'size': stamp.size,
      'modified': stamp.modified,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<String?> albumFingerprint(String albumKey) async {
    final rows = await (await _open()).query(
      'album_fingerprints',
      columns: ['fingerprint'],
      where: 'album_key = ?',
      whereArgs: [albumKey],
    );
    return rows.isEmpty ? null : rows.first['fingerprint'] as String;
  }

  @override
  Future<void> saveAlbumFingerprint(String albumKey, String fingerprint) async {
    await (await _open()).insert('album_fingerprints', {
      'album_key': albumKey,
      'fingerprint': fingerprint,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
