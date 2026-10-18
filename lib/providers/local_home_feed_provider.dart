import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/providers/library_browse_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/services/library_database.dart';

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
  if (!ref.watch(settingsProvider.select((s) => s.localLibraryEnabled))) {
    return const [];
  }
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
