import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sistrum/services/animated_artwork/animated_artwork_download.dart';
import 'package:sistrum/services/library/database/sqlite_helpers.dart' as sqlite;
import 'package:sistrum/utils/logging/logger.dart';
import 'package:sqflite/sqflite.dart';

enum AnimatedArtworkKind {
  album,
  artist;

  static AnimatedArtworkKind? parse(String? value) => switch (value) {
    'album' => album,
    'artist' => artist,
    _ => null,
  };
}

/// What is recorded for one album or artist.
enum AnimatedArtworkStatus {
  /// Downloaded automatically from Apple Music.
  auto,

  /// Chosen by the user, from the catalog or from a local file.
  manual,

  /// Looked up and not matched, or the match had no usable video. Retried
  /// after [kAnimatedArtworkRetryAfter].
  notFound,

  /// The user removed the video. Automatic downloads never replace it.
  reset;

  static AnimatedArtworkStatus? parse(String? value) => switch (value) {
    'auto' => auto,
    'manual' => manual,
    'notFound' => notFound,
    'reset' => reset,
    _ => null,
  };
}

/// How long a legitimate miss waits before the automatic lookup tries again.
const kAnimatedArtworkRetryAfter = Duration(days: 14);

class AnimatedArtworkRecord {
  const AnimatedArtworkRecord({
    required this.kind,
    required this.key,
    required this.status,
    this.fileName,
    this.remoteId,
    this.checkedAtMs = 0,
    this.width,
    this.height,
    this.bytes,
  });

  final AnimatedArtworkKind kind;

  /// The durable identity, see [animatedAlbumKey] and [animatedArtistKey].
  final String key;
  final AnimatedArtworkStatus status;

  /// File inside the animated artwork folder. Null when there is no video.
  final String? fileName;

  /// Apple's identifier for the chosen video, used to share one file between
  /// records that resolved to the same remote video. Never used for playback.
  final String? remoteId;
  final int checkedAtMs;
  final int? width;
  final int? height;
  final int? bytes;

  bool get hasVideo =>
      (status == AnimatedArtworkStatus.auto ||
          status == AnimatedArtworkStatus.manual) &&
      fileName != null;

  String get id => animatedArtworkId(kind, key);
}

/// Album identity: the title and album artist, normalized. Edition markers
/// stay in the title, so a deluxe release never shares a video with the
/// standard one.
String animatedAlbumKey(String albumTitle, String albumArtist) =>
    '${_normalizeKeyPart(albumTitle)}|${_normalizeKeyPart(albumArtist)}';

/// Artist identity: the artist name, normalized the same way as other lookups.
String animatedArtistKey(String artistName) => _normalizeKeyPart(artistName);

String animatedArtworkId(AnimatedArtworkKind kind, String key) =>
    '${kind.name}|$key';

String _normalizeKeyPart(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

abstract interface class AnimatedArtworkState {
  Future<Map<String, AnimatedArtworkRecord>> readAll();
  Future<void> put(AnimatedArtworkRecord record);
  Future<void> remove(AnimatedArtworkKind kind, String key);
  Future<void> clear();
}

class MemoryAnimatedArtworkState implements AnimatedArtworkState {
  final _records = <String, AnimatedArtworkRecord>{};

  @override
  Future<Map<String, AnimatedArtworkRecord>> readAll() async =>
      Map.unmodifiable(_records);

  @override
  Future<void> put(AnimatedArtworkRecord record) async {
    _records[record.id] = record;
  }

  @override
  Future<void> remove(AnimatedArtworkKind kind, String key) async {
    _records.remove(animatedArtworkId(kind, key));
  }

  @override
  Future<void> clear() async => _records.clear();
}

/// Records in their own database, so the library schema is unchanged.
class AnimatedArtworkDb implements AnimatedArtworkState {
  AnimatedArtworkDb({Future<Database> Function()? open}) : _openDatabase = open;

  final Future<Database> Function()? _openDatabase;
  final _database = sqlite.SingleFlightInitializer<Database>();

  static const _schemaVersion = 1;

  Future<Database> _open() => _database.getOrCreate(
    _openDatabase ??
        () => sqlite.openAppDatabase(
          'animated_artwork.db',
          version: _schemaVersion,
          onCreate: _create,
          onUpgrade: (db, oldVersion, newVersion) async {},
        ),
  );

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE animated_artwork (
        kind TEXT NOT NULL,
        artwork_key TEXT NOT NULL,
        status TEXT NOT NULL,
        file_name TEXT,
        remote_id TEXT,
        checked_at INTEGER NOT NULL DEFAULT 0,
        width INTEGER,
        height INTEGER,
        bytes INTEGER,
        PRIMARY KEY (kind, artwork_key)
      )
    ''');
  }

  @override
  Future<Map<String, AnimatedArtworkRecord>> readAll() async {
    final db = await _open();
    final rows = await db.query('animated_artwork');
    final records = <String, AnimatedArtworkRecord>{};
    for (final row in rows) {
      final kind = AnimatedArtworkKind.parse(row['kind'] as String?);
      final status = AnimatedArtworkStatus.parse(row['status'] as String?);
      if (kind == null || status == null) continue;
      final key = row['artwork_key'] as String;
      final record = AnimatedArtworkRecord(
        kind: kind,
        key: key,
        status: status,
        fileName: row['file_name'] as String?,
        remoteId: row['remote_id'] as String?,
        checkedAtMs: row['checked_at'] as int? ?? 0,
        width: row['width'] as int?,
        height: row['height'] as int?,
        bytes: row['bytes'] as int?,
      );
      records[record.id] = record;
    }
    return records;
  }

  @override
  Future<void> put(AnimatedArtworkRecord record) async {
    final db = await _open();
    await db.insert('animated_artwork', {
      'kind': record.kind.name,
      'artwork_key': record.key,
      'status': record.status.name,
      'file_name': record.fileName,
      'remote_id': record.remoteId,
      'checked_at': record.checkedAtMs,
      'width': record.width,
      'height': record.height,
      'bytes': record.bytes,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> remove(AnimatedArtworkKind kind, String key) async {
    final db = await _open();
    await db.delete(
      'animated_artwork',
      where: 'kind = ? AND artwork_key = ?',
      whereArgs: [kind.name, key],
    );
  }

  @override
  Future<void> clear() async {
    final db = await _open();
    await db.delete('animated_artwork');
  }
}

enum AnimatedArtworkSaveOutcome {
  saved,

  /// A newer decision (manual choice, Reset, Clear or a change of setting)
  /// arrived first. Nothing was published, and the old video is untouched.
  superseded,

  /// The record would replace a video that the rules say must stay.
  kept,
}

/// A ticket belongs to one entity revision and one cache generation.
class AnimatedArtworkTicket {
  const AnimatedArtworkTicket(this.generation, this.revision);
  final int generation, revision;
}

/// Serializes publication, Reset and Clear for animated artwork.
///
/// Rules:
/// - A manual choice always wins and invalidates in-flight automatic work
///   for the same entity.
/// - An automatic result only fills an entity with no record, or one that
///   was a legitimate miss. It never replaces a video or a Reset.
/// - Reset removes the video file for that entity and records suppression.
/// - Clear invalidates everything in flight and removes every video.
/// - Files are shared only through the same remote id; a file is deleted
///   only when no record references it.
class AnimatedArtworkStore {
  AnimatedArtworkStore({required this.state, required this.directory});

  final AnimatedArtworkState state;
  final Future<Directory> Function() directory;
  final _log = AppLogger('AnimatedArtwork');

  Future<void> _tail = Future.value();
  int _generation = 0;
  final _revisions = <String, int>{};

  int get generation => _generation;

  AnimatedArtworkTicket ticketFor(AnimatedArtworkKind kind, String key) =>
      AnimatedArtworkTicket(
        _generation,
        _revisions[animatedArtworkId(kind, key)] ?? 0,
      );

  bool _current(AnimatedArtworkKind kind, String key, AnimatedArtworkTicket t) =>
      t.generation == _generation &&
      t.revision == (_revisions[animatedArtworkId(kind, key)] ?? 0);

  void _bump(AnimatedArtworkKind kind, String key) {
    final id = animatedArtworkId(kind, key);
    _revisions[id] = (_revisions[id] ?? 0) + 1;
  }

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

  Future<Map<String, AnimatedArtworkRecord>> readAll() => state.readAll();

  Future<AnimatedArtworkRecord?> recordFor(
    AnimatedArtworkKind kind,
    String key,
  ) async => (await state.readAll())[animatedArtworkId(kind, key)];

  Future<File?> fileFor(AnimatedArtworkRecord record) async {
    final name = record.fileName;
    if (!record.hasVideo || name == null || p.basename(name) != name) {
      return null;
    }
    final file = File(p.join((await directory()).path, name));
    return await file.exists() ? file : null;
  }

  /// A new file in the staging folder, on the same filesystem as the video
  /// folder, so publication is a rename.
  Future<File> newStagingFile() async {
    final staging = Directory(p.join((await directory()).path, '.staging'));
    await staging.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return File(p.join(staging.path, 'v_$stamp.part'));
  }

  /// Publishes a downloaded or imported video for one entity. The staged
  /// file is consumed on success and deleted on every other outcome.
  Future<AnimatedArtworkSaveOutcome> publishVideo({
    required AnimatedArtworkKind kind,
    required String key,
    required DownloadedAnimatedVideo video,
    required AnimatedArtworkStatus status,
    String? remoteId,
    AnimatedArtworkTicket? ticket,
    Future<bool> Function()? mayCommit,
  }) {
    if (status == AnimatedArtworkStatus.manual ||
        status == AnimatedArtworkStatus.reset) {
      _bump(kind, key);
    }
    final expected = ticket ?? ticketFor(kind, key);
    return _mutate(() async {
      var committed = false;
      try {
        bool rulesAllow(AnimatedArtworkRecord? existing) =>
            status != AnimatedArtworkStatus.auto ||
            existing == null ||
            existing.status == AnimatedArtworkStatus.notFound;

        Future<bool> allowed() async {
          if (!_current(kind, key, expected)) return false;
          if (mayCommit != null && !await mayCommit()) return false;
          return _current(kind, key, expected);
        }

        if (!_current(kind, key, expected)) {
          return AnimatedArtworkSaveOutcome.superseded;
        }
        final existing = await recordFor(kind, key);
        if (!rulesAllow(existing)) {
          return AnimatedArtworkSaveOutcome.kept;
        }
        if (!await allowed()) {
          return AnimatedArtworkSaveOutcome.superseded;
        }

        final dir = await directory();
        await dir.create(recursive: true);
        final records = await state.readAll();
        String? fileName;
        if (remoteId != null) {
          for (final other in records.values) {
            if (other.remoteId == remoteId &&
                other.fileName != null &&
                await _fileExists(dir, other.fileName!)) {
              fileName = other.fileName;
              break;
            }
          }
        }
        final staged = File(video.file.path);
        if (fileName == null) {
          final digest = sha256
              .convert(utf8.encode(animatedArtworkId(kind, key)))
              .toString()
              .substring(0, 24);
          final stamp = DateTime.now().microsecondsSinceEpoch;
          fileName = '${kind.name}_${digest}_$stamp.mp4';
          await staged.rename(p.join(dir.path, fileName));
          committed = true;
        } else {
          await _deleteBestEffort(staged.path);
        }
        if (!await allowed()) {
          if (!committed) return AnimatedArtworkSaveOutcome.superseded;
          if (!_isShared(records, fileName) &&
              !await _recordReferences(kind, key, fileName)) {
            await _deleteBestEffort(p.join(dir.path, fileName));
          }
          return AnimatedArtworkSaveOutcome.superseded;
        }
        try {
          await state.put(
            AnimatedArtworkRecord(
              kind: kind,
              key: key,
              status: status,
              fileName: fileName,
              remoteId: remoteId,
              checkedAtMs: DateTime.now().millisecondsSinceEpoch,
              width: video.width,
              height: video.height,
              bytes: video.bytes,
            ),
          );
        } catch (_) {
          // The previous record still points at its own file, so only the
          // file this attempt just published is removed.
          if (committed &&
              existing?.fileName != fileName &&
              !_isShared(records, fileName)) {
            await _deleteBestEffort(p.join(dir.path, fileName));
          }
          rethrow;
        }
        if (existing?.fileName != null && existing!.fileName != fileName) {
          await _pruneUnreferenced(dir, existing.fileName!);
        }
        return AnimatedArtworkSaveOutcome.saved;
      } finally {
        if (!committed) {
          await _deleteBestEffort(video.file.path);
        }
      }
    });
  }

  /// Records a miss (`notFound`) or Reset. Reset removes the video.
  Future<AnimatedArtworkSaveOutcome> recordWithoutVideo({
    required AnimatedArtworkKind kind,
    required String key,
    required AnimatedArtworkStatus status,
    AnimatedArtworkTicket? ticket,
    Future<bool> Function()? mayCommit,
  }) {
    if (status == AnimatedArtworkStatus.reset) _bump(kind, key);
    final expected = ticket ?? ticketFor(kind, key);
    return _mutate(() async {
      if (!_current(kind, key, expected)) {
        return AnimatedArtworkSaveOutcome.superseded;
      }
      if (mayCommit != null && !await mayCommit()) {
        return AnimatedArtworkSaveOutcome.superseded;
      }
      final existing = await recordFor(kind, key);
      if (status == AnimatedArtworkStatus.notFound &&
          existing != null &&
          existing.status != AnimatedArtworkStatus.notFound) {
        return AnimatedArtworkSaveOutcome.kept;
      }
      if (!_current(kind, key, expected)) {
        return AnimatedArtworkSaveOutcome.superseded;
      }
      await state.put(
        AnimatedArtworkRecord(
          kind: kind,
          key: key,
          status: status,
          checkedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      final previous = existing?.fileName;
      if (previous != null) {
        await _pruneUnreferenced(await directory(), previous);
      }
      return AnimatedArtworkSaveOutcome.saved;
    });
  }

  Future<int> sizeBytes() async {
    final dir = await directory();
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  /// Removes every video and record. Anything in flight is superseded.
  Future<void> clearAll() {
    _generation++;
    return _mutate(() async {
      // If the database cannot be cleared, keep the files so the records
      // still point at real data.
      await state.clear();
      final dir = await directory();
      if (await dir.exists()) {
        try {
          await dir.delete(recursive: true);
        } on FileSystemException catch (error) {
          _log.w('Video artwork cache cleanup failed: $error');
        }
      }
    });
  }

  Future<bool> _recordReferences(
    AnimatedArtworkKind kind,
    String key,
    String name,
  ) async => (await recordFor(kind, key))?.fileName == name;

  static bool _isShared(Map<String, AnimatedArtworkRecord> records, String name) =>
      records.values.any((r) => r.fileName == name);

  static Future<bool> _fileExists(Directory dir, String name) =>
      File(p.join(dir.path, name)).exists();

  Future<void> _pruneUnreferenced(Directory dir, String name) async {
    if (p.basename(name) != name) return;
    try {
      if (_isShared(await state.readAll(), name)) return;
      await _deleteBestEffort(p.join(dir.path, name));
    } catch (error) {
      _log.w('Unused video pruning failed: $error');
    }
  }

  Future<void> _deleteBestEffort(String path) async {
    final file = File(path);
    if (!await file.exists()) return;
    try {
      await file.delete();
    } on FileSystemException catch (error) {
      _log.w('Video file cleanup failed: $error');
    }
  }
}
