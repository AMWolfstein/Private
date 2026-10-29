import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sistrum/utils/best_effort_delete.dart';

const _playlistCoverMaxDimension = 1024;
const _playlistCoverMaxStoredBytes = 2 * 1024 * 1024;

typedef PlaylistCoverResize =
    Future<void> Function({
      required String inputPath,
      required String outputPath,
      required int maxDimension,
    });
typedef PlaylistCoverProbe =
    Future<({int width, int height})?> Function(String path);

/// Device-local playlist cover files. Imported images are normalized into
/// bounded JPEGs inside the app's `playlist_covers` directory.
class PlaylistCoverFiles {
  PlaylistCoverFiles({
    required PlaylistCoverProbe probeCover,
    required PlaylistCoverResize resizeCover,
  }) : _probeCover = probeCover,
       _resizeCover = resizeCover;

  final PlaylistCoverProbe _probeCover;
  final PlaylistCoverResize _resizeCover;

  Future<Directory> playlistCoversDir() async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appDir.path, 'playlist_covers'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> deletePrivatePlaylistCover(String path) async {
    try {
      final root = await (await playlistCoversDir()).resolveSymbolicLinks();
      final file = File(path);
      final resolved = await file.resolveSymbolicLinks();
      if (p.isWithin(root, resolved)) {
        await file.delete();
        final parent = Directory(p.dirname(resolved));
        if (p.dirname(parent.path) == root &&
            p.basename(parent.path).startsWith('cover-') &&
            await parent.list().isEmpty) {
          await parent.delete();
        }
      }
    } on FileSystemException catch (_) {
      /* Unreferenced files can be reclaimed later. */
    }
  }

  Future<String> normalizePlaylistCoverFile(String sourceFilePath) async {
    final coversDir = await playlistCoversDir();
    // Playlist IDs are opaque backup data, never filesystem path components.
    // Versioned destinations leave the live cover intact until the DB commits.
    final version = await coversDir.createTemp('cover-');
    final destPath = p.join(version.path, 'image.jpg');
    final tempPath = p.join(version.path, 'working.jpg');
    var published = false;
    try {
      final dimensions = await _probeCover(sourceFilePath);
      final longestEdge = dimensions == null
          ? _playlistCoverMaxDimension
          : (dimensions.width > dimensions.height
                ? dimensions.width
                : dimensions.height);
      var targetDimension = longestEdge
          .clamp(64, _playlistCoverMaxDimension)
          .toInt();
      while (true) {
        await _resizeCover(
          inputPath: sourceFilePath,
          outputPath: tempPath,
          maxDimension: targetDimension,
        );
        if (await File(tempPath).length() <= _playlistCoverMaxStoredBytes) {
          break;
        }
        if (targetDimension <= 64) {
          throw StateError('Normalized playlist cover exceeds the size limit');
        }
        targetDimension = (targetDimension * 3 ~/ 4)
            .clamp(64, targetDimension)
            .toInt();
      }
      await File(tempPath).rename(destPath);
      published = true;
      return destPath;
    } finally {
      await deleteBestEffort(File(tempPath));
      if (!published) await deleteBestEffort(version, recursive: true);
    }
  }

  Future<bool> playlistCoverNeedsNormalization(String path) async {
    final file = File(path);
    if (!await file.exists()) return false;
    if (p.extension(path).toLowerCase() != '.jpg' ||
        await file.length() > _playlistCoverMaxStoredBytes) {
      return true;
    }
    final dimensions = await _probeCover(path);
    return dimensions == null ||
        dimensions.width > _playlistCoverMaxDimension ||
        dimensions.height > _playlistCoverMaxDimension;
  }
}
