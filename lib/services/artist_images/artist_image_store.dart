import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sistrum/utils/logging/logger.dart';
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

enum ArtistImageSaveOutcome { saved, superseded }

/// A ticket belongs to one artist revision and one cache generation.
class ArtistImageWriteTicket {
  const ArtistImageWriteTicket(this.generation, this.revision);
  final int generation, revision;
}

/// Serializes file/database publication, reset and Clear. Only successfully
/// recorded generations become visible; old files survive failed publication.
class ArtistImageStore {
  ArtistImageStore({required this.state, required this.directory});
  final ArtistImageState state;
  final Future<Directory> Function() directory;
  Future<void> _tail = Future.value();
  int _generation = 0;
  final _revisions = <String, int>{};
  int get generation => _generation;
  ArtistImageWriteTicket ticketFor(String key) =>
      ArtistImageWriteTicket(_generation, _revisions[key] ?? 0);
  bool _current(String key, ArtistImageWriteTicket ticket) =>
      ticket.generation == _generation &&
      ticket.revision == (_revisions[key] ?? 0);

  Future<T> _mutate<T>(Future<T> Function() action) {
    final done = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        done.complete(await action());
      } catch (error, stack) {
        done.completeError(error, stack);
      }
    });
    return done.future;
  }

  Future<Map<String, ArtistImageRecord>> readAll() => state.readAll();
  Future<File?> fileFor(ArtistImageRecord record) async {
    final name = record.fileName;
    if (!record.hasPhoto || name == null || p.basename(name) != name) {
      return null;
    }
    final file = File(p.join((await directory()).path, name));
    return await file.exists() ? file : null;
  }

  Future<ArtistImageSaveOutcome> savePhoto({
    required String key,
    int? deezerId,
    required Uint8List bytes,
    required ArtistImageStatus status,
    ArtistImageWriteTicket? ticket,
    Future<bool> Function()? mayCommit,
  }) {
    if (status != ArtistImageStatus.auto) {
      _revisions[key] = (_revisions[key] ?? 0) + 1;
    }
    final expected = ticket ?? ticketFor(key);
    return _mutate(() async {
      Future<bool> allowed() async {
        if (!_current(key, expected)) return false;
        if (mayCommit != null && !await mayCommit()) return false;
        if (!_current(key, expected)) return false;
        return status != ArtistImageStatus.auto ||
            !(await state.readAll()).containsKey(key);
      }

      if (!await allowed()) return ArtistImageSaveOutcome.superseded;
      final dir = await directory();
      await dir.create(recursive: true);
      final staging = await dir.createTemp('.write-');
      File? published;
      var recorded = false;
      try {
        final name =
            'artist_${sha256.convert(utf8.encode(key)).toString().substring(0, 24)}_${p.basename(staging.path)}.jpg';
        final staged = await File(
          p.join(staging.path, 'photo'),
        ).writeAsBytes(bytes, flush: true);
        if (!await allowed()) return ArtistImageSaveOutcome.superseded;
        final previous = (await state.readAll())[key];
        if (!await allowed()) return ArtistImageSaveOutcome.superseded;
        published = await staged.rename(p.join(dir.path, name));
        if (!await allowed()) return ArtistImageSaveOutcome.superseded;
        await state.put(
          ArtistImageRecord(
            artistKey: key,
            status: status,
            deezerId: deezerId,
            fileName: name,
          ),
        );
        recorded = true;
        if (previous?.fileName != null) {
          await _pruneUnreferenced(dir, previous!.fileName!);
        }
        return ArtistImageSaveOutcome.saved;
      } finally {
        if (!recorded && published != null) {
          await _deleteBestEffort(published.path);
        }
        try {
          await staging.delete(recursive: true);
        } on FileSystemException catch (error) {
          AppLogger('ArtistImages').w('Photo staging cleanup failed: $error');
        }
      }
    });
  }

  Future<ArtistImageSaveOutcome> recordWithoutPhoto(
    String key,
    ArtistImageStatus status, {
    ArtistImageWriteTicket? ticket,
    Future<bool> Function()? mayCommit,
  }) {
    if (status != ArtistImageStatus.notFound) {
      _revisions[key] = (_revisions[key] ?? 0) + 1;
    }
    final expected = ticket ?? ticketFor(key);
    return _mutate(() async {
      if (!_current(key, expected) ||
          (mayCommit != null && !await mayCommit()) ||
          !_current(key, expected)) {
        return ArtistImageSaveOutcome.superseded;
      }
      final records = await state.readAll();
      if (status == ArtistImageStatus.notFound && records.containsKey(key)) {
        return ArtistImageSaveOutcome.superseded;
      }
      if (!_current(key, expected)) return ArtistImageSaveOutcome.superseded;
      final previous = records[key];
      await state.put(ArtistImageRecord(artistKey: key, status: status));
      if (previous?.fileName != null) {
        await _pruneUnreferenced(await directory(), previous!.fileName!);
      }
      return ArtistImageSaveOutcome.saved;
    });
  }

  Future<void> _pruneUnreferenced(Directory dir, String name) async {
    if (p.basename(name) != name) return;
    try {
      if ((await state.readAll()).values.any((r) => r.fileName == name)) return;
      await _deleteBestEffort(p.join(dir.path, name));
    } catch (error) {
      AppLogger('ArtistImages').w('Unused photo pruning failed: $error');
    }
  }

  Future<int> sizeBytes() async {
    final dir = await directory();
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  Future<void> clearAll() {
    _generation++;
    return _mutate(() async {
      // If the database cannot be cleared, leave every old photo intact.
      await state.clear();
      final dir = await directory();
      if (await dir.exists()) {
        try {
          await dir.delete(recursive: true);
        } on FileSystemException catch (error) {
          AppLogger('ArtistImages').w('Photo cache cleanup failed: $error');
        }
      }
    });
  }

  static Future<void> _deleteBestEffort(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException catch (error) {
      AppLogger('ArtistImages').w('Unused photo cleanup failed: $error');
    }
  }
}
