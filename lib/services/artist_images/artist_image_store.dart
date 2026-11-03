import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sistrum/services/artist_images/deezer_artist_search.dart';
import 'package:sistrum/services/library/database/sqlite_helpers.dart'
    as sqlite;

/// Largest portrait accepted from Deezer, in bytes.
const kArtistImageMaxBytes = 5 * 1024 * 1024;

/// What happened for one artist. Any record stops the automatic search for
/// that artist; only Clear lets it run again.
enum ArtistImageStatus {
  /// Found automatically on Deezer.
  auto,

  /// Chosen by the user from the Find artist image sheet.
  manual,

  /// No exact match on Deezer, or no portrait for the match.
  notFound,

  /// The user removed the photo and wants the album cover back.
  reset;

  static ArtistImageStatus? parse(String? value) => switch (value) {
    'auto' => auto,
    'manual' => manual,
    'notFound' => notFound,
    'reset' => reset,
    _ => null,
  };
}

class ArtistImageRecord {
  const ArtistImageRecord({
    required this.artistKey,
    required this.status,
    this.deezerId,
    this.fileName,
  });

  final String artistKey;
  final ArtistImageStatus status;
  final int? deezerId;

  /// The file inside the artist images folder. Null when there is no photo.
  final String? fileName;

  bool get hasPhoto =>
      (status == ArtistImageStatus.auto ||
          status == ArtistImageStatus.manual) &&
      fileName != null;
}

/// The key for an artist name: the same normalization as name matching, so
/// "AC/DC" and "ac dc" share one photo.
String artistImageKey(String name) => normalizeArtistName(name);

abstract interface class ArtistImageState {
  Future<Map<String, ArtistImageRecord>> readAll();
  Future<void> put(ArtistImageRecord record);
  Future<void> clear();
}

class MemoryArtistImageState implements ArtistImageState {
  final _records = <String, ArtistImageRecord>{};

  @override
  Future<Map<String, ArtistImageRecord>> readAll() async =>
      Map.unmodifiable(_records);

  @override
  Future<void> put(ArtistImageRecord record) async {
    _records[record.artistKey] = record;
  }

  @override
  Future<void> clear() async => _records.clear();
}

/// Artist photo records in their own small database, so the library schema
/// stays unchanged.
class ArtistImageDb implements ArtistImageState {
  ArtistImageDb({Future<Database> Function()? open}) : _openDatabase = open;

  final Future<Database> Function()? _openDatabase;
  final _database = sqlite.SingleFlightInitializer<Database>();

  static const _schemaVersion = 1;

  Future<Database> _open() => _database.getOrCreate(
    _openDatabase ??
        () => sqlite.openAppDatabase(
          'artist_images.db',
          version: _schemaVersion,
          onCreate: _create,
          onUpgrade: (db, oldVersion, newVersion) async {},
        ),
  );

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE artist_image (
        artist_key TEXT PRIMARY KEY,
        status TEXT NOT NULL,
        deezer_id INTEGER,
        file_name TEXT
      )
    ''');
  }

  @override
  Future<Map<String, ArtistImageRecord>> readAll() async {
    final db = await _open();
    final rows = await db.query('artist_image');
    final records = <String, ArtistImageRecord>{};
    for (final row in rows) {
      final status = ArtistImageStatus.parse(row['status'] as String?);
      if (status == null) continue;
      final key = row['artist_key'] as String;
      records[key] = ArtistImageRecord(
        artistKey: key,
        status: status,
        deezerId: row['deezer_id'] as int?,
        fileName: row['file_name'] as String?,
      );
    }
    return records;
  }

  @override
  Future<void> put(ArtistImageRecord record) async {
    final db = await _open();
    await db.insert('artist_image', {
      'artist_key': record.artistKey,
      'status': record.status.name,
      'deezer_id': record.deezerId,
      'file_name': record.fileName,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> clear() async {
    final db = await _open();
    await db.delete('artist_image');
  }
}

/// Keeps artist photos in one folder inside the app's own storage and the
/// state of each artist in [state].
class ArtistImageStore {
  ArtistImageStore({required this.state, required this.directory});

  final ArtistImageState state;
  final Future<Directory> Function() directory;

  Future<Map<String, ArtistImageRecord>> readAll() => state.readAll();

  /// The photo file for [record], or null when it has none or the file is
  /// missing.
  Future<File?> fileFor(ArtistImageRecord record) async {
    final name = record.fileName;
    if (!record.hasPhoto || name == null) return null;
    final file = File(p.join((await directory()).path, name));
    return file.existsSync() ? file : null;
  }

  /// Writes a photo completely before it is recorded, so a half-written file
  /// never becomes an artist's photo. The previous photo, if any, is removed.
  Future<void> savePhoto({
    required String key,
    required DeezerArtist artist,
    required Uint8List bytes,
    required ArtistImageStatus status,
  }) async {
    final dir = await directory();
    await dir.create(recursive: true);
    final name = 'artist_${artist.id}.jpg';
    final target = File(p.join(dir.path, name));
    final temp = File('${target.path}.part');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(target.path);

    final previous = (await state.readAll())[key];
    if (previous?.fileName != null && previous!.fileName != name) {
      await _deleteBestEffort(p.join(dir.path, previous.fileName!));
    }
    await state.put(
      ArtistImageRecord(
        artistKey: key,
        status: status,
        deezerId: artist.id,
        fileName: name,
      ),
    );
  }

  /// Records an artist without a photo (not found, or reset by the user) and
  /// removes any photo it had.
  Future<void> recordWithoutPhoto(String key, ArtistImageStatus status) async {
    final previous = (await state.readAll())[key];
    final name = previous?.fileName;
    if (name != null) {
      await _deleteBestEffort(p.join((await directory()).path, name));
    }
    await state.put(ArtistImageRecord(artistKey: key, status: status));
  }

  /// Bytes used by the photo folder.
  Future<int> sizeBytes() async {
    final dir = await directory();
    if (!dir.existsSync()) return 0;
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  /// Removes every photo and every record, so automatic lookups run again.
  Future<void> clearAll() async {
    final dir = await directory();
    if (dir.existsSync()) {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Best-effort: remaining files are harmless, and their records are
        // cleared below.
      }
    }
    await state.clear();
  }

  static Future<void> _deleteBestEffort(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // The old photo is unused once its record is replaced.
    }
  }
}
