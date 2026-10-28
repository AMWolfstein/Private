import 'package:sistrum/services/library/library_database.dart';
import 'package:sistrum/services/embedded_cover_resolver.dart';
import 'package:sistrum/utils/path_match_keys.dart';
import 'package:sistrum/utils/duplicate_quality_policy.dart';

/// Clear every index of a deleted file, but never delete a retained alias.
Future<int> deleteReviewedDuplicateCopies({
  required List<IsrcDuplicateEntry> entries,
  required List<IsrcDuplicateEntry> retainedEntries,
  required Future<bool> Function(String path) deleteFile,
  required Future<void> Function(String path) removePhysicalFile,
  required Future<void> Function(IsrcDuplicateEntry entry) removeIndexEntry,
}) async {
  var deleted = 0;
  for (final entry in entries) {
    final path = EmbeddedCoverResolver.cleanFilePath(entry.filePath);
    if (isPhysicalFileRetained(
      path,
      retainedEntries.map((entry) => entry.filePath),
    )) {
      await removeIndexEntry(entry);
    } else {
      if (!await deleteFile(path)) continue;
      await removePhysicalFile(entry.filePath);
    }
    deleted++;
  }
  return deleted;
}

class DuplicateCleanupPlan {
  final List<IsrcDuplicateEntry> retainedEntries;
  final List<IsrcDuplicateEntry> entriesToDelete;
  final int groupCount;

  const DuplicateCleanupPlan({
    required this.retainedEntries,
    required this.entriesToDelete,
    required this.groupCount,
  });
}

/// Keeps the highest-quality entry from every verified duplicate group and
/// schedules every remaining copy for deletion.
///
/// Sort defensively so a stale/manual review ordering cannot select a worse
/// lossy copy just because it has a higher sample rate.
DuplicateCleanupPlan buildKeepBestAllDuplicatePlan(
  List<IsrcDuplicateGroup> groups,
) {
  final retainedEntries = <IsrcDuplicateEntry>[];
  final entriesToDelete = <IsrcDuplicateEntry>[];
  var groupCount = 0;

  for (final group in groups) {
    if (group.entries.length < 2 ||
        !group.entries.every(hasComparableDuplicateQuality)) {
      continue;
    }
    final entries = List<IsrcDuplicateEntry>.of(group.entries)
      ..sort(compareDuplicateQuality);
    groupCount++;
    retainedEntries.add(entries.first);
    entriesToDelete.addAll(entries.skip(1));
  }

  return DuplicateCleanupPlan(
    retainedEntries: List.unmodifiable(retainedEntries),
    entriesToDelete: List.unmodifiable(entriesToDelete),
    groupCount: groupCount,
  );
}
