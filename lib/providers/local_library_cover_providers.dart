import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/library_database_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/services/library/database/library_database.dart';

/// Cover lookups for album and collection rows: request keys, the batched
/// first-cover search, and the hook tests use to observe it.

class LocalLibraryCoverRequest {
  final String? isrc;
  final String trackName;
  final String artistName;

  const LocalLibraryCoverRequest({
    this.isrc,
    required this.trackName,
    required this.artistName,
  });

  @override
  bool operator ==(Object other) {
    return other is LocalLibraryCoverRequest &&
        other.isrc == isrc &&
        other.trackName == trackName &&
        other.artistName == artistName;
  }

  @override
  int get hashCode => Object.hash(isrc, trackName, artistName);
}

class LocalLibraryCoverBatchRequest {
  final List<LocalLibraryCoverRequest> tracks;

  const LocalLibraryCoverBatchRequest(this.tracks);

  @override
  bool operator ==(Object other) {
    if (other is! LocalLibraryCoverBatchRequest) return false;
    if (other.tracks.length != tracks.length) return false;
    for (var i = 0; i < tracks.length; i++) {
      if (other.tracks[i] != tracks[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(tracks);
}

String? _nonEmptyCoverPath(Map<String, dynamic>? json) {
  final coverPath = json?['coverPath'] as String?;
  final trimmed = coverPath?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

final localLibraryCoverProvider = FutureProvider.autoDispose
    .family<String?, LocalLibraryCoverRequest>((ref, request) {
      ref.watch(
        localLibraryProvider.select((state) => state.loadedIndexVersion),
      );
      return ref
          .read(libraryDatabaseProvider)
          .findExisting(
            isrc: request.isrc,
            trackName: request.trackName,
            artistName: request.artistName,
          )
          .then(_nonEmptyCoverPath);
    });

/// Batch lookup hook so tests can observe the chunked first-cover search.
final libraryExistingBatchLoaderProvider =
    Provider<
      Future<List<Map<String, dynamic>?>> Function(
        List<LocalLibraryBatchLookupRequest>,
      )
    >(
      (ref) =>
          (requests) =>
              ref.read(libraryDatabaseProvider).findExistingBatch(requests),
    );

final localLibraryFirstCoverProvider = FutureProvider.autoDispose
    .family<String?, LocalLibraryCoverBatchRequest>((ref, request) async {
      ref.watch(
        localLibraryProvider.select((state) => state.loadedIndexVersion),
      );
      // OPT-PERF-006: resolve the batch in ordered chunks and stop at the
      // first usable cover, so a large playlist with an early cover does not
      // wait for every member lookup. Chunking preserves the exact matching
      // precedence of a single full-batch lookup.
      final load = ref.watch(libraryExistingBatchLoaderProvider);
      const chunkSize = 450;
      final lookups = [
        for (final track in request.tracks)
          LocalLibraryBatchLookupRequest(
            isrc: track.isrc,
            trackName: track.trackName,
            artistName: track.artistName,
          ),
      ];
      for (var start = 0; start < lookups.length; start += chunkSize) {
        final end = (start + chunkSize).clamp(0, lookups.length);
        final rows = await load(lookups.sublist(start, end));
        for (final row in rows) {
          final cover = _nonEmptyCoverPath(row);
          if (cover != null) return cover;
        }
      }
      return null;
    });
