import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sistrum/utils/logging/logger.dart';

/// Publish stable thumbnail names only after the scan's index transaction has
/// succeeded. Scanning itself keeps writing to a fresh staging generation, so a
/// failed/cancelled extraction cannot overwrite covers from the old index.
/// Each atomic rename precedes its DB reference; interrupted publication leaves
/// either a complete staged cover or a complete stable cover, never a missing one.
Future<int> stabilizePublishedLibraryCovers(
  Database db,
  String sourceId,
  Directory directory, {
  required bool Function() canPublish,
}) async {
  final root = p.normalize(directory.absolute.path);
  final prefix = '$root/full_scan_';
  String cursor = '';
  var published = 0;
  while (canPublish()) {
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT cover_path FROM library WHERE source_id = ?
      AND substr(cover_path, 1, length(?)) = ? AND cover_path > ?
      ORDER BY cover_path LIMIT 128
    ''',
      [sourceId, prefix, prefix, cursor],
    );
    if (rows.isEmpty) break;
    for (final row in rows) {
      final path = row['cover_path'] as String;
      cursor = path;
      if (!canPublish()) return published;
      final normalized = p.normalize(path);
      if (!p.isWithin(root, normalized)) continue;
      if (await FileSystemEntity.type(normalized, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      final name = p.basename(normalized);
      if (!{
        '.jpg',
        '.jpeg',
        '.png',
        '.webp',
        '.image',
      }.contains(p.extension(name).toLowerCase())) {
        continue;
      }
      final target = File(p.join(root, name));
      File? temporary;
      try {
        // Create a unique sibling; rename is atomic on the app-private filesystem.
        temporary = File(
          '${target.path}.publish-${DateTime.now().microsecondsSinceEpoch}',
        );
        await File(normalized).copy(temporary.path);
        if (!canPublish()) return published;
        await temporary.rename(target.path);
        temporary = null;
        await db.rawUpdate(
          'UPDATE library SET cover_path = ? WHERE source_id = ? AND cover_path = ?',
          [target.path, sourceId, path],
        );
        published++;
      } on FileSystemException catch (error) {
        // The already committed staged reference remains valid on failure.
        AppLogger(
          'LibraryCovers',
        ).w('Could not publish stable thumbnail: $error');
      } finally {
        if (temporary != null) {
          try {
            await temporary.delete();
          } on FileSystemException catch (error) {
            AppLogger(
              'LibraryCovers',
            ).w('Could not clean thumbnail staging file: $error');
          }
        }
      }
    }
    if (rows.length < 128) break;
  }
  return published;
}
