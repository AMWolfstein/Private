import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sistrum/constants/app_info.dart';
import 'package:sistrum/services/platform_bridge.dart';
import 'package:sistrum/services/user_profile_store.dart';
import 'package:sistrum/utils/best_effort_delete.dart';
import 'package:sistrum/utils/logger.dart';

Future<void> _writeBackupMetadataInBackground(
  String path,
  Map<String, dynamic> metadata,
  String? collectionsJson,
) => Isolate.run(() {
  if (collectionsJson == null) {
    File(path).writeAsStringSync(jsonEncode(metadata), flush: true);
    return;
  }
  // The collections exporter already encoded this trusted object on its
  // worker. Passing the immutable string avoids cloning its full map graph
  // onto another worker. Write it directly, preserving metadata key order.
  final output = File(path).openSync(mode: FileMode.write);
  final buffer = StringBuffer();
  try {
    buffer.write('{');
    var first = true;
    for (final entry in metadata.entries) {
      if (!first) buffer.write(',');
      first = false;
      buffer
        ..write(jsonEncode(entry.key))
        ..write(':');
      if (entry.key != 'data') {
        buffer.write(jsonEncode(entry.value));
        continue;
      }
      final data = entry.value as Map<String, dynamic>;
      buffer.write('{');
      var firstData = true;
      for (final field in data.entries) {
        if (!firstData) buffer.write(',');
        firstData = false;
        buffer
          ..write(jsonEncode(field.key))
          ..write(':');
        if (field.key == 'collections') {
          output.writeStringSync(buffer.toString());
          buffer.clear();
          output.writeStringSync(collectionsJson);
        } else {
          buffer.write(jsonEncode(field.value));
        }
      }
      buffer.write('}');
    }
    buffer.write('}');
    output
      ..writeStringSync(buffer.toString())
      ..flushSync();
  } finally {
    output.closeSync();
  }
});

/// Parsed contents of a backup file. Cover payloads stay on disk until restore
/// consumes them.
class BackupBundle {
  final int formatVersion;
  final DateTime? createdAt;
  final Map<String, dynamic>? settings;
  final UserProfile? profile;
  final Map<String, dynamic> collections;
  final Map<String, dynamic> playlistCovers;
  final String? _temporaryDirectoryPath;

  const BackupBundle({
    required this.formatVersion,
    required this.createdAt,
    required this.settings,
    required this.collections,
    required this.playlistCovers,
    this.profile,
    String? temporaryDirectoryPath,
  }) : _temporaryDirectoryPath = temporaryDirectoryPath;

  bool get hasSettings => settings != null && settings!.isNotEmpty;
  bool get hasCollections => collections.isNotEmpty;
  Future<void> cleanup() async {
    final path = _temporaryDirectoryPath;
    if (path == null || path.isEmpty) return;
    try {
      final directory = Directory(path);
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {}
  }

  int _collectionListCount(String key) {
    final value = collections[key];
    return value is List ? value.length : 0;
  }

  int get likedCount => _collectionListCount('loved');
  int get playlistCount => _collectionListCount('playlists');
  int get favoriteArtistCount => _collectionListCount('favoriteArtists');

  bool get isEmpty =>
      !hasSettings &&
      profile == null &&
      likedCount == 0 &&
      playlistCount == 0 &&
      favoriteArtistCount == 0;
}

/// The export would exceed a limit the importer enforces, so it is refused
/// instead of publishing a backup that cannot be restored.
class BackupTooLargeException implements Exception {
  const BackupTooLargeException(this.message);

  final String message;

  @override
  String toString() => 'BackupTooLargeException: $message';
}

/// Why a backup file could not be restored; the restore page words each one.
enum BackupParseFailure {
  /// Not a Sistrum backup archive at all.
  notBackupArchive,

  /// A backup written by a different format version.
  unsupportedVersion,

  /// A Sistrum archive whose metadata is missing, too large or malformed.
  corruptArchive,

  /// The file could not be read from storage or extracted.
  unreadable,
}

class BackupParseException implements Exception {
  const BackupParseException(this.reason, [this.cause]);

  final BackupParseFailure reason;
  final Object? cause;

  @override
  String toString() => 'BackupParseException: ${reason.name}';
}

class BackupService {
  static final _log = AppLogger('BackupService');

  static const String magic = 'sistrum-backup';
  static const int formatVersion = 3;
  static const String fileExtension = 'sbk';
  // Restore decodes metadata.json in memory; keep in sync with the native
  // archive reader.
  static const int _maxMetadataBytes = 32 << 20;
  static const int _maxCoverBytes = 20 << 20;
  static const int _maxAllCoversBytes = 256 << 20;
  static const int _maxProfilePhotoBytes = 2 << 20;
  static const String _profilePhotoEntry = 'profile/avatar.png';

  static String encode(Map<String, dynamic> envelope) =>
      const JsonEncoder.withIndent('  ').convert(envelope);

  static Future<File> writeBackupArchive({
    required Map<String, dynamic>? settings,
    required Map<String, dynamic> collections,
    String? collectionsJson,
    required Map<String, Map<String, String>> playlistCoverFiles,
    Directory? outputDirectory,
    Directory? temporaryDirectory,
    UserProfile? profile,
  }) async {
    if (collectionsJson != null && collections.isNotEmpty) {
      throw ArgumentError('Provide collections as a map or encoded JSON');
    }
    final output = await _newBackupFile(outputDirectory);
    final tempRoot = temporaryDirectory ?? await getTemporaryDirectory();
    final staging = await Directory(
      p.join(
        tempRoot.path,
        'sistrum_backup_${DateTime.now().microsecondsSinceEpoch}',
      ),
    ).create(recursive: true);
    final metadataFile = File(p.join(staging.path, 'metadata.json'));
    final partFile = File('${output.path}.part');

    try {
      final coverManifest = <String, Map<String, String>>{};
      var coverIndex = 0;
      for (final entry in playlistCoverFiles.entries) {
        final sourcePath = entry.value['path'] ?? '';
        final source = File(sourcePath);
        if (sourcePath.isEmpty || !await source.exists()) continue;
        var ext = (entry.value['ext'] ?? p.extension(sourcePath)).toLowerCase();
        if (!RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(ext)) ext = '.jpg';
        final archiveName = 'covers/cover_${coverIndex++}$ext';
        coverManifest[entry.key] = {'ext': ext, 'file': archiveName};
      }

      final photoPath = profile?.photoPath;
      if (photoPath != null &&
          await File(photoPath).length() > _maxProfilePhotoBytes) {
        throw const FormatException('Profile photo is too large');
      }
      final metadata = {
        'magic': magic,
        'format_version': formatVersion,
        'app': AppInfo.appName,
        'app_version': AppInfo.displayVersion,
        'created_at': DateTime.now().toIso8601String(),
        'data': {
          'settings': ?settings,
          if (profile != null)
            'profile': {
              'name': profile.name,
              if (photoPath != null) 'photo': _profilePhotoEntry,
            },
          if (collectionsJson != null || collections.isNotEmpty)
            'collections': collections,
          if (coverManifest.isNotEmpty) 'playlist_covers': coverManifest,
        },
      };
      await writeBackupMetadata(
        metadataFile.path,
        metadata,
        collectionsJson: collectionsJson,
      );

      if (await metadataFile.length() > _maxMetadataBytes) {
        throw const BackupTooLargeException(
          'Backup collections exceed the supported metadata limit',
        );
      }
      var coverBytes = 0;
      for (final entry in coverManifest.keys) {
        final size = await File(playlistCoverFiles[entry]!['path']!).length();
        coverBytes += size;
        if (size > _maxCoverBytes || coverBytes > _maxAllCoversBytes) {
          throw const BackupTooLargeException(
            'Backup artwork exceeds the supported limit',
          );
        }
      }
      if (await partFile.exists()) await partFile.delete();
      final archiveFiles = <({String path, String name, bool store})>[
        (path: metadataFile.path, name: 'metadata.json', store: false),
        if (photoPath != null)
          (path: photoPath, name: _profilePhotoEntry, store: true),
      ];
      for (final entry in coverManifest.entries) {
        final sourcePath = playlistCoverFiles[entry.key]?['path'];
        if (sourcePath == null) continue;
        archiveFiles.add((
          path: sourcePath,
          name: entry.value['file']!,
          store: true,
        ));
      }
      final result = await PlatformBridge.runNativeDataJob({
        'operation': 'backup_archive_write',
        'output_path': partFile.path,
        'files': [
          for (final file in archiveFiles)
            {'path': file.path, 'name': file.name, 'store': file.store},
        ],
      });
      if (result['published'] != true ||
          result['count'] != archiveFiles.length) {
        throw const FormatException('Incomplete native backup archive');
      }
      if (await output.exists()) await output.delete();
      await partFile.rename(output.path);
      _log.i('Streaming backup written to ${output.path}');
      return output;
    } finally {
      await deleteBestEffort(staging, recursive: true);
      await deleteBestEffort(partFile);
    }
  }

  static Future<File> _newBackupFile([Directory? outputDirectory]) async {
    final dir = outputDirectory ?? await getApplicationDocumentsDirectory();
    final backupsDir =
        outputDirectory ?? Directory(p.join(dir.path, 'backups'));
    await backupsDir.create(recursive: true);
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return File(
      p.join(backupsDir.path, 'sistrum_mobile_backup_$stamp.$fileExtension'),
    );
  }

  /// Throws [BackupParseException] when [path] cannot be restored.
  static Future<BackupBundle> parseFile(
    String path, {
    Directory? temporaryDirectory,
  }) async {
    final tempRoot = temporaryDirectory ?? await getTemporaryDirectory();
    final bool isZip;
    try {
      isZip = await _hasZipHeader(File(path));
    } on FileSystemException catch (error) {
      throw BackupParseException(BackupParseFailure.unreadable, error);
    }
    if (!isZip) {
      throw const BackupParseException(BackupParseFailure.notBackupArchive);
    }
    return _parseArchiveNative(path, tempRoot);
  }

  static Future<bool> _hasZipHeader(File file) async {
    final header = await file
        .openRead(0, 4)
        .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
    return header.length == 4 &&
        header[0] == 0x50 &&
        header[1] == 0x4b &&
        header[2] == 0x03 &&
        header[3] == 0x04;
  }

  static Future<BackupBundle> _parseArchiveNative(
    String path,
    Directory temporary,
  ) async {
    String? stagingPath;
    try {
      await temporary.create(recursive: true);
      final result = await PlatformBridge.runNativeDataJob({
        'operation': 'backup_archive_read',
        'input_path': path,
        'temporary_directory': temporary.path,
      });
      stagingPath = result['temporary_directory_path'] as String?;
      if (result['published'] != true || stagingPath == null) {
        throw const FormatException('Incomplete native backup staging');
      }
      // ZIP decompression and large payloads remain native/on disk; only the
      // bounded metadata is hydrated into Flutter models on a Dart worker.
      return await Isolate.run(() {
        final root =
            jsonDecode(
                  File(result['metadata_path'] as String).readAsStringSync(),
                )
                as Map;
        final data = root['data'] as Map;
        final rawProfile = data['profile'] as Map?;
        return BackupBundle(
          formatVersion: root['format_version'] as int,
          createdAt: DateTime.tryParse(root['created_at'] as String? ?? ''),
          settings: _mapOrNull(data['settings']),
          profile: rawProfile == null
              ? null
              : UserProfile(
                  name: rawProfile['name'] as String,
                  photoPath: result['profile_photo_path'] as String?,
                ),
          collections: _mapOrEmpty(data['collections']),
          playlistCovers: _mapOrEmpty(result['playlist_covers']),
          temporaryDirectoryPath: stagingPath,
        );
      });
    } catch (error) {
      if (stagingPath != null) {
        await deleteBestEffort(Directory(stagingPath), recursive: true);
      }
      _log.w('Backup archive native parse failed: $error');
      throw BackupParseException(
        error is FormatException
            ? BackupParseFailure.corruptArchive
            : BackupParseFailure.unreadable,
        error,
      );
    }
  }

  /// [collectionsJson] is the trusted JSON object from the collection export
  /// worker. Its empty placeholder in metadata retains the normal key order.
  @visibleForTesting
  static Future<void> writeBackupMetadata(
    String path,
    Map<String, dynamic> metadata, {
    String? collectionsJson,
  }) => _writeBackupMetadataInBackground(path, metadata, collectionsJson);

  static Map<String, dynamic>? _mapOrNull(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  static Map<String, dynamic> _mapOrEmpty(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
}
