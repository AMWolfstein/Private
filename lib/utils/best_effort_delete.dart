import 'dart:io';

/// Deletes [entity] when it exists and ignores any failure. Use it only for
/// cleanup that has no recovery path, where a leftover file is acceptable.
Future<void> deleteBestEffort(
  FileSystemEntity entity, {
  bool recursive = false,
}) async {
  try {
    if (await entity.exists()) await entity.delete(recursive: recursive);
  } catch (_) {}
}
