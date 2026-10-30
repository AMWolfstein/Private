import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sistrum/services/library/collections/library_collections_playlist_covers.dart';
import 'package:sistrum/utils/files/best_effort_delete.dart';

/// Writes each playlist cover from a backup into [coversDir] and points the
/// playlist at the new file, or drops the backup's device path when no cover
/// can be restored. Every written path is appended to [prepared] so the caller
/// can delete them if the restore does not commit.
Future<void> rewriteBackupPlaylistCovers({
  required Map<String, dynamic> normalized,
  required Map<String, dynamic>? coverImages,
  required Directory coversDir,
  required PlaylistCoverFiles covers,
  required List<String> prepared,
}) async {
  final playlistsRaw = normalized['playlists'];
  if (playlistsRaw is List) {
    final rewritten = <Map<String, dynamic>>[];
    for (final entry in playlistsRaw.whereType<Map<Object?, Object?>>()) {
      final playlist = Map<String, dynamic>.from(entry);
      final id = playlist['id'] as String?;
      String? newCoverPath;
      final coverEntry = (id != null && coverImages != null)
          ? coverImages[id]
          : null;
      if (id != null && coverEntry is Map) {
        final data = coverEntry['data'] as String?;
        final restoredPath = coverEntry['path'] as String?;
        final ext = (coverEntry['ext'] as String?) ?? '.jpg';
        if ((data != null && data.isNotEmpty) ||
            (restoredPath != null && restoredPath.isNotEmpty)) {
          try {
            final staging = await coversDir.createTemp('restore-');
            final safeExt = RegExp(r'^\.[a-zA-Z0-9]{1,8}$').hasMatch(ext)
                ? ext
                : '.jpg';
            final sourcePath = p.join(staging.path, 'source$safeExt');
            final source = File(sourcePath);
            try {
              if (restoredPath != null && restoredPath.isNotEmpty) {
                await File(restoredPath).copy(source.path);
              } else {
                await source.writeAsBytes(base64Decode(data!), flush: true);
              }
              newCoverPath = await covers.normalizePlaylistCoverFile(
                sourcePath,
              );
              prepared.add(newCoverPath);
            } finally {
              await deleteBestEffort(staging, recursive: true);
            }
          } catch (_) {
            newCoverPath = null;
          }
        }
      }
      // Always replace the backup's device-specific path: either with the
      // freshly written local cover, or drop it so a stale path is not kept.
      if (newCoverPath != null) {
        playlist['coverImagePath'] = newCoverPath;
      } else {
        playlist.remove('coverImagePath');
      }
      rewritten.add(playlist);
    }
    normalized['playlists'] = rewritten;
  }
}
