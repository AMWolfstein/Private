import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/library/library_database_provider.dart';
import 'package:sistrum/providers/library/library_tag_credits_provider.dart';
import 'package:sistrum/providers/library/local_library_provider.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/utils/text/library_initial.dart';

/// Global offsets use the same ascending/descending name order as the pages.
typedef LibraryAlphabetRequest = ({
  bool artists,
  bool albumArtists,
  bool descending,
});
typedef LibraryAlphabetEntry = ({String label, int offset});

final libraryAlphabetProvider = FutureProvider.autoDispose
    .family<List<LibraryAlphabetEntry>, LibraryAlphabetRequest>((
      ref,
      request,
    ) async {
      ref.watch(localLibraryProvider.select((s) => s.loadedIndexVersion));
      final credits = ref.watch(tagCreditScopeProvider);
      final rows = await ref
          .read(libraryDatabaseProvider)
          .getBrowseAlphabetRows(
            LibraryBrowseDbQuery(
              albumArtistsOnly: request.albumArtists,
              sortMode: request.descending ? 'z-a' : 'a-z',
              credits: credits,
            ),
            artists: request.artists,
          );
      var offset = 0;
      final seen = <String>{};
      final result = <LibraryAlphabetEntry>[];
      for (final row in rows) {
        final label = librarySectionInitial(row['name'] as String? ?? '');
        if (seen.add(label)) result.add((label: label, offset: offset));
        offset += (row['item_count'] as num?)?.toInt() ?? 0;
      }
      return result;
    });
