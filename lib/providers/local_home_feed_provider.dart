import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/library_browse_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/services/library/library_database.dart';

const localHomeShelfLimit = 12;

/// The feed never hydrates the whole library. Ordering and limits run in SQLite.
final localHomeTrackLoaderProvider =
    Provider<Future<QueueLibraryDbPage> Function()>(
      (ref) =>
          () => LibraryDatabase.instance.getQueueTrackPageResult(
            const QueueLibraryDbQuery(
              limit: localHomeShelfLimit,
              sortMode: 'latest',
              includeSingleTrackAlbums: true,
            ),
          ),
    );

final localHomeTracksProvider = FutureProvider<List<LocalLibraryItem>>((
  ref,
) async {
  ref.watch(localLibraryProvider.select((s) => s.loadedIndexVersion));
  final page = await ref.watch(localHomeTrackLoaderProvider)();
  return page.rows
      .map(
        (row) => LocalLibraryItem.fromJson(
          Map<String, dynamic>.from(row['item'] as Map),
        ),
      )
      .where((item) => item.filePath.trim().isNotEmpty)
      .toList(growable: false);
});

LibraryBrowseRequest localHomeBrowseRequest({
  bool artists = false,
  String sort = 'latest',
}) => (
  artists: artists,
  artist: null,
  search: '',
  sort: sort,
  limit: localHomeShelfLimit,
  completeness: null,
);
