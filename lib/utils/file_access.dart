import 'dart:io';

import 'package:sistrum/services/platform_bridge.dart';
import 'package:sistrum/services/source_deletion_events.dart';

class FileAccessStat {
  final int? size;
  final DateTime? modified;

  const FileAccessStat({this.size, this.modified});
}

bool isContentUri(String? path) {
  return path != null && path.startsWith('content://');
}

/// Pattern matching CUE virtual path suffixes like #track01, #track12, etc.
final _cueTrackSuffix = RegExp(r'#track\d+$');

/// Local CUE rows are always backed by a `.cue` sheet. A real audio file may
/// legitimately contain `#trackNN` in its name, so only paths on a `.cue` base
/// are virtual there. SAF document URIs encode `#` in real names, so a trailing
/// suffix is unambiguous for them.
final _cueSheetTrackSuffix = RegExp(r'\.cue#track\d+$', caseSensitive: false);

const cueVirtualTrackRequiresSplitMessage =
    'This CUE track is virtual. Use Split into Tracks first.';

/// Whether the path is a CUE virtual path (contains #trackNN suffix).
bool isCueVirtualPath(String? path) {
  if (path == null || !_cueTrackSuffix.hasMatch(path)) return false;
  return isContentUri(path) || _cueSheetTrackSuffix.hasMatch(path);
}

/// Whether [path] names a CUE sheet or one of its virtual rows, so deleting it
/// directly would remove a file shared by every sibling track.
bool isCueBackedPath(String? path) =>
    isCueVirtualPath(path) || (path?.toLowerCase().endsWith('.cue') ?? false);

/// Whether a library row is backed by a CUE sheet, by its path or by the
/// scanner format (`cue+flac`), so deleting the row must never delete a file.
bool isCueBackedRow(String? path, String? format) =>
    isCueBackedPath(path) || (format?.startsWith('cue+') ?? false);

/// Strip the #trackNN suffix from a CUE virtual path to get the base .cue path.
/// Returns the path unchanged if it's not a CUE virtual path, so a real file
/// whose name merely ends in `#trackNN` keeps its own path.
String stripCueTrackSuffix(String path) {
  return isCueVirtualPath(path) ? path.replaceFirst(_cueTrackSuffix, '') : path;
}

Future<bool> fileExists(String? path) async {
  if (path == null || path.isEmpty) return false;
  final realPath = isCueVirtualPath(path) ? stripCueTrackSuffix(path) : path;
  if (isContentUri(realPath)) {
    return PlatformBridge.safExists(realPath);
  }
  return File(realPath).exists();
}

/// Bounded, tri-state checks for destructive library cleanup. Unknown results
/// retain their database rows. CUE tracks are checked against the backing file.
Future<Map<String, bool?>> fileExistenceByPath(List<String> paths) async {
  final realPaths = {for (final path in paths) path: stripCueTrackSuffix(path)};
  final results = <String, bool?>{};
  final unique = realPaths.values.toSet();
  final saf = unique.where(isContentUri).toList(growable: false);
  const batchSize = 64;
  for (var start = 0; start < saf.length; start += batchSize) {
    final end = start + batchSize < saf.length ? start + batchSize : saf.length;
    final batch = saf.sublist(start, end);
    try {
      results.addAll(await PlatformBridge.safExistsBatch(batch));
    } catch (_) {
      // Missing native method on an older build is also inconclusive.
    }
  }
  final local = unique.where((path) => !isContentUri(path)).toList();
  const concurrency = 16;
  for (var start = 0; start < local.length; start += concurrency) {
    final end = start + concurrency < local.length
        ? start + concurrency
        : local.length;
    await Future.wait(
      local.sublist(start, end).map((path) async {
        if (path.isEmpty) return;
        try {
          final stat = await File(path).stat();
          if (stat.type != FileSystemEntityType.notFound) {
            results[path] = true;
          } else {
            // Dart's stat also returns notFound for permission errors. Opening
            // exposes the OS error without reading the audio file's contents.
            final handle = await File(path).open();
            await handle.close();
            results[path] = true;
          }
        } on FileSystemException catch (error) {
          final code = error.osError?.errorCode;
          final absent = code == 2 || code == (Platform.isWindows ? 3 : 20);
          results[path] = absent ? false : null;
        } catch (_) {
          results[path] = null;
        }
      }),
    );
  }
  return {for (final item in realPaths.entries) item.key: results[item.value]};
}

/// Deletes [path] and reports whether the file is confirmed absent afterward.
///
/// SAF providers are allowed to reject a delete request by returning `false`.
/// Callers that also remove a Library row must only do so when this returns
/// `true`, otherwise the app would hide a file that still exists on storage.
Future<bool> deleteFile(
  String? path, {
  SourceDeletionEvents? deletionEvents,
}) async {
  if (path == null || path.isEmpty) return false;
  if (path.startsWith('EXISTS:')) {
    path = path.substring(7).trim();
    if (path.isEmpty) return false;
  }
  // CUE virtual paths should NOT be deleted through this function —
  // deleting album.cue would remove ALL tracks. Callers should handle
  // CUE deletion specially (e.g. only delete when all tracks are removed).
  if (isCueVirtualPath(path)) return false;
  bool confirmedAbsent;
  try {
    if (isContentUri(path)) {
      final deleted = await PlatformBridge.safDelete(path);
      confirmedAbsent =
          deleted || (await fileExistenceByPath([path]))[path] == false;
    } else {
      try {
        await File(path).delete();
        confirmedAbsent = true;
      } on FileSystemException {
        // exists()/stat() can hide permission failures as "not found".
        // Only the tri-state probe's explicit absence permits index cleanup.
        confirmedAbsent = (await fileExistenceByPath([path]))[path] == false;
      }
    }
  } catch (_) {
    return false;
  }
  if (confirmedAbsent) {
    await (deletionEvents ?? SourceDeletionEvents.instance).publish(path);
  }
  return confirmedAbsent;
}

Future<FileAccessStat?> fileStat(String? path) async {
  if (path == null || path.isEmpty) return null;
  final realPath = isCueVirtualPath(path) ? stripCueTrackSuffix(path) : path;
  if (isContentUri(realPath)) {
    final stat = await PlatformBridge.safStat(realPath);
    final exists = stat['exists'] as bool? ?? true;
    if (!exists) return null;
    return FileAccessStat(
      size: stat['size'] as int?,
      modified: stat['modified'] != null
          ? DateTime.fromMillisecondsSinceEpoch(stat['modified'] as int)
          : null,
    );
  }

  final stat = await FileStat.stat(realPath);
  if (stat.type == FileSystemEntityType.notFound) {
    // Dart stat hides every OS error behind notFound. A metadata-only lookup
    // exposes the errno without opening or copying audio on the normal path.
    try {
      return FileAccessStat(size: await File(realPath).length());
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      if (code == 2 || code == (Platform.isWindows ? 3 : 20)) return null;
      rethrow;
    }
  }
  return FileAccessStat(size: stat.size, modified: stat.modified);
}
