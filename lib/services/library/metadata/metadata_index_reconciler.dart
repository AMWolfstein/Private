import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sistrum/models/local_library_item.dart';
import 'package:sistrum/services/library/metadata/library_edited_metadata.dart';
import 'package:sistrum/services/native/media_file_bridge.dart';
import 'package:sistrum/utils/logging/logger.dart';

/// Why a saved file's fresh tags did not reach the browse index.
enum MetadataIndexFailure { read, database }

/// Whether a saved edit is browsable yet.
class MetadataIndexResult {
  final MetadataIndexFailure? failure;
  final Object? error;

  const MetadataIndexResult.indexed() : failure = null, error = null;
  const MetadataIndexResult.stale(
    MetadataIndexFailure this.failure,
    this.error,
  );

  bool get indexed => failure == null;
}

/// Publishes a saved file's fresh tags and artwork to the library index.
///
/// [MetadataPersistenceService] only writes the file. This operation rereads
/// the saved tags, refreshes the extracted cover and upserts the row, so the
/// caller never has to know the storage, artwork or database protocols; it
/// only refreshes providers and reports [MetadataIndexResult].
class MetadataIndexReconciler {
  final Future<Map<String, dynamic>> Function(String) read;
  final Future<Map<String, dynamic>> Function(String, String) extractCover;
  final Future<Directory> Function() supportDirectory;
  final Future<void> Function(
    Map<String, dynamic> json, {
    required String sourceId,
  })
  upsert;

  const MetadataIndexReconciler({
    this.read = MediaFileBridge.readFileMetadata,
    this.extractCover = MediaFileBridge.extractCoverToFile,
    this.supportDirectory = getApplicationSupportDirectory,
    required this.upsert,
  });

  Future<MetadataIndexResult> reconcile(LocalLibraryItem item) async {
    final Map<String, dynamic> fresh;
    try {
      fresh = await read(item.filePath);
    } catch (error) {
      return MetadataIndexResult.stale(MetadataIndexFailure.read, error);
    }
    if (fresh['error'] != null) {
      return MetadataIndexResult.stale(
        MetadataIndexFailure.read,
        fresh['error'],
      );
    }
    final json = localMetadataAfterEdit(item, fresh);
    final coverPath = await _refreshCover(item.filePath);
    // A failed extraction keeps the previous cover reference instead of
    // clearing it; reference-aware pruning reclaims the old image only once the
    // database stops referring to it.
    if (coverPath != null) json['coverPath'] = coverPath;
    try {
      await upsert(json, sourceId: item.sourceId);
    } catch (error) {
      return MetadataIndexResult.stale(MetadataIndexFailure.database, error);
    }
    return const MetadataIndexResult.indexed();
  }

  Future<String?> _refreshCover(String filePath) async {
    try {
      final directory = Directory(
        '${(await supportDirectory()).path}/library_covers',
      );
      await directory.create(recursive: true);
      final path =
          '${directory.path}/edited_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final cover = await extractCover(filePath, path);
      final file = File(path);
      if (cover['error'] == null &&
          await file.exists() &&
          await file.length() > 0) {
        return path;
      }
      if (await file.exists()) await file.delete();
    } catch (error) {
      AppLogger(
        'SongMetadata',
      ).w('Saved tags but could not refresh artwork: $error');
    }
    return null;
  }
}
