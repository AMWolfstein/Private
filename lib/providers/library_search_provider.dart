import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/models/unified_library_item.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/services/library/library_database.dart';
import 'package:sistrum/services/library/library_playlist_search.dart';
import 'package:sistrum/services/library/library_search.dart';

typedef LibrarySearchRequest = ({
  String query,
  LibrarySearchKind kind,
  int limit,
  int offset,
});

/// Resolve the selected record by its source and ID, without matching titles
/// that may also belong to another edition or remix.
final librarySearchTrackProvider = FutureProvider.autoDispose
    .family<UnifiedLibraryItem?, ({String source, String id})>((
      ref,
      key,
    ) async {
      if (key.source != 'local') return null;
      final row = await LibraryDatabase.instance.getById(key.id);
      return row == null
          ? null
          : UnifiedLibraryItem.fromLocalLibrary(LocalLibraryItem.fromJson(row));
    });

final librarySearchProvider = FutureProvider.autoDispose
    .family<List<LibrarySearchHit>, LibrarySearchRequest>((ref, request) async {
      final query = LibrarySearchQuery(request.query);
      if (query.terms.isEmpty) return const [];
      if (request.kind == LibrarySearchKind.playlists) {
        final playlists = ref.watch(
          libraryCollectionsProvider.select((state) => state.playlists),
        );
        return searchLibraryPlaylists(
          playlists: playlists,
          query: request.query,
          limit: request.limit,
          offset: request.offset,
        );
      }
      ref.watch(localLibraryProvider.select((s) => s.loadedIndexVersion));
      return LibraryDatabase.instance.searchLibrary(
        query: request.query,
        kind: request.kind,
        limit: request.limit,
        offset: request.offset,
      );
    });
