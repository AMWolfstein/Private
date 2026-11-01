import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/core/models/track.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/services/native/media_file_bridge.dart';
import 'package:sistrum/utils/files/file_access.dart';

/// Shared local-only resolver for phone playback and headless media browsers.
class LocalTrackResolver {
  const LocalTrackResolver(this.library);
  final LibraryDatabase library;
  Future<List<LocalLibraryItem?>> resolve(List<Track> tracks) async {
    if (tracks.isEmpty) return const [];
    final localFuture = library.findExistingBatch([
      for (final track in tracks)
        LocalLibraryBatchLookupRequest(
          id: (track.source ?? '').toLowerCase() == 'local' ? track.id : null,
          isrc: track.isrc,
          trackName: track.name,
          artistName: track.artistName,
        ),
    ]);
    final localMatches = await localFuture;

    final results = List<LocalLibraryItem?>.filled(tracks.length, null);
    final existsChecks = <String, Future<bool>>{};
    final unknownSafPaths = <String>{};
    final safPaths = <String>{
      for (final row in localMatches)
        if (isContentUri(
          stripCueTrackSuffix(row?['filePath']?.toString() ?? ''),
        ))
          stripCueTrackSuffix(row!['filePath'].toString()),
    }.toList(growable: false);
    for (var start = 0; start < safPaths.length; start += 64) {
      final batch = safPaths.sublist(
        start,
        (start + 64).clamp(0, safPaths.length),
      );
      try {
        final checks = await MediaFileBridge.safExistsBatch(batch);
        for (final path in batch) {
          final exists = checks[path];
          if (exists != null) {
            existsChecks[path] = Future.value(exists);
          } else {
            unknownSafPaths.add(path);
          }
        }
      } catch (_) {
        // Older bindings may lack the batch API; retain per-file fallback.
        unknownSafPaths.addAll(batch);
      }
    }
    var next = 0;
    final workerCount = tracks.length < 8 ? tracks.length : 8;

    Future<bool> pathExists(String path) {
      final realPath = stripCueTrackSuffix(path);
      return existsChecks.putIfAbsent(realPath, () => fileExists(path));
    }

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= tracks.length) return;
        final row = localMatches[index];
        final localPath = row?['filePath']?.toString() ?? '';
        if (localPath.isNotEmpty && await pathExists(localPath)) {
          results[index] = LocalLibraryItem.fromJson(row!);
        }
      }
    }

    await Future.wait(List.generate(workerCount, (_) => worker()));
    return results;
  }
}
