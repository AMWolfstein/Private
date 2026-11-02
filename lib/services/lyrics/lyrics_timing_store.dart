import 'package:sqflite/sqflite.dart';
import 'package:sistrum/services/library/database/sqlite_helpers.dart'
    as sqlite;
import 'package:sistrum/services/lyrics/online_lyrics_search.dart';

/// What the library knows about a song's embedded lyrics. [timing] is null
/// when the file has no lyrics at all.
class LyricsTimingRecord {
  const LyricsTimingRecord({required this.fingerprint, required this.timing});

  final String fingerprint;
  final LyricsTiming? timing;

  bool get isSynced =>
      timing == LyricsTiming.wordSynced || timing == LyricsTiming.lineSynced;
}

/// The file identity a record belongs to. A changed file, or a rescan that
/// moved its modification time, makes the stored record stale.
String lyricsFingerprint(String filePath, int? fileModTime) =>
    '$filePath|${fileModTime ?? 0}';

abstract interface class LyricsTimingState {
  Future<Map<String, LyricsTimingRecord>> readAll();
  Future<void> put(String songId, LyricsTimingRecord record);
}

class MemoryLyricsTimingState implements LyricsTimingState {
  final _records = <String, LyricsTimingRecord>{};

  @override
  Future<Map<String, LyricsTimingRecord>> readAll() async =>
      Map.unmodifiable(_records);

  @override
  Future<void> put(String songId, LyricsTimingRecord record) async {
    _records[songId] = record;
  }
}

/// Persists lyrics timing per song in its own small database, so the library
/// schema and its native scanner stay unchanged.
class LyricsTimingDb implements LyricsTimingState {
  LyricsTimingDb({Future<Database> Function()? open}) : _openDatabase = open;

  final Future<Database> Function()? _openDatabase;
  final _database = sqlite.SingleFlightInitializer<Database>();

  static const _schemaVersion = 1;

  Future<Database> _open() => _database.getOrCreate(
    _openDatabase ??
        () => sqlite.openAppDatabase(
          'lyrics_timing.db',
          version: _schemaVersion,
          onCreate: _create,
          onUpgrade: (db, oldVersion, newVersion) async {},
        ),
  );

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE lyrics_timing (
        song_id TEXT PRIMARY KEY,
        fingerprint TEXT NOT NULL,
        timing TEXT NOT NULL
      )
    ''');
  }

  static String _encode(LyricsTiming? timing) => switch (timing) {
    null => 'none',
    LyricsTiming.wordSynced => 'word',
    LyricsTiming.lineSynced => 'line',
    LyricsTiming.plain => 'plain',
  };

  static LyricsTiming? _decode(String value) => switch (value) {
    'word' => LyricsTiming.wordSynced,
    'line' => LyricsTiming.lineSynced,
    'plain' => LyricsTiming.plain,
    _ => null,
  };

  @override
  Future<Map<String, LyricsTimingRecord>> readAll() async {
    final db = await _open();
    final rows = await db.query('lyrics_timing');
    return {
      for (final row in rows)
        row['song_id'] as String: LyricsTimingRecord(
          fingerprint: row['fingerprint'] as String,
          timing: _decode(row['timing'] as String),
        ),
    };
  }

  @override
  Future<void> put(String songId, LyricsTimingRecord record) async {
    final db = await _open();
    await db.insert('lyrics_timing', {
      'song_id': songId,
      'fingerprint': record.fingerprint,
      'timing': _encode(record.timing),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
