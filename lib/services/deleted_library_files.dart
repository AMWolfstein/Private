import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/services/embedded_cover_resolver.dart';
import 'package:sistrum/services/library/library_database_models.dart';
import 'package:sistrum/utils/file_access.dart';

/// The outcome of one local-library deletion pass.
class DeletedLibraryTracks {
  const DeletedLibraryTracks({
    required this.deletedIds,
    required this.requested,
  });

  /// Library row IDs whose file (or virtual CUE row) was removed.
  final List<String> deletedIds;

  /// Rows the pass was asked to delete.
  final int requested;

  int get deletedCount => deletedIds.length;
}

/// Deletes the files behind [items] and clears their library rows. A CUE-backed
/// row only drops its virtual row because the sheet and audio are shared with
/// its siblings; any other row deletes its file, and every index entry for a
/// deleted file is cleared together. Confirmation, selection state and messages
/// stay with the caller.
///
/// Index cleanup runs even when a later file deletion throws, so successfully
/// deleted files never keep a stale row.
Future<DeletedLibraryTracks> deleteLocalLibraryTracks(
  ProviderContainer container,
  Iterable<LocalLibraryItem> items,
) async {
  final deletedIds = <String>[];
  final deletedPaths = <String>{};
  final cueIds = <String>[];
  var requested = 0;
  try {
    for (final item in items) {
      requested++;
      if (isCueBackedRow(item.filePath, item.format)) {
        cueIds.add(item.id);
        deletedIds.add(item.id);
        continue;
      }
      final path = EmbeddedCoverResolver.cleanFilePath(item.filePath);
      if (!await deleteFile(path)) continue;
      deletedPaths.add(path);
      deletedIds.add(item.id);
    }
  } finally {
    await removeDeletedLibraryFileEntries(container, deletedPaths);
    if (cueIds.isNotEmpty) {
      await container.read(localLibraryProvider.notifier).removeItems(cueIds);
    }
  }
  return DeletedLibraryTracks(deletedIds: deletedIds, requested: requested);
}

/// Call only after deletion succeeds. Scanned rows can share a physical file,
/// so every index must be cleared together. Capture the app container before
/// I/O so leaving the screen cannot prevent cleanup after a slow deletion.
Future<void> removeDeletedLibraryFileEntries(
  ProviderContainer container,
  Iterable<String> filePaths,
) async {
  final paths = filePaths.toSet();
  if (paths.isEmpty) return;
  await container
      .read(localLibraryProvider.notifier)
      .removePhysicalFiles(paths);
}
