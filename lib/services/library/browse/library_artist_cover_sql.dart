import 'package:sistrum/services/library/browse/library_browse_filters.dart';
import 'package:sistrum/services/library/browse/library_tag_credits.dart';
import 'package:sistrum/services/library/database/library_schema.dart';

/// The cover and sample file that represent an artist: the newest owned
/// non-Single release, else the newest owned Single, else the newest credited
/// song. The Artists directory and Search both select them with this SQL, so
/// the same artist shows the same picture in both.
///
/// [keyColumn] is the artist's normalized name column in the enclosing query,
/// and [fields] lists the credit fields (`'album_artist'`, `'artist'`) the
/// fallback song may come from.
({String cover, String sample}) artistCoverAndSampleSql({
  required String keyColumn,
  required String fields,
}) {
  const table = LibraryTagCreditsCache.tempTable;
  String featuredProjection(String projection, {bool single = false}) =>
      '''(
      SELECT $projection FROM $table owned
      JOIN ${LibrarySchema.visibleView} newest ON newest.id = owned.item_id
      WHERE owned.field = 'album_artist' AND owned.name_key = $keyColumn
      GROUP BY newest.album_key
      HAVING ${single ? '' : 'NOT'} (MAX(COALESCE(newest.total_tracks, 0)) = 1 AND MAX(COALESCE(newest.total_discs, 1)) <= 1)
      ORDER BY MAX(${metadataReleaseDateSql('newest.release_date')}) DESC,
        MAX(COALESCE(newest.sort_added, 0)) DESC, newest.album_key
      LIMIT 1
    )''';
  final featuredCover = featuredProjection(
    "COALESCE(MAX(NULLIF(newest.cover_path, '')), '')",
  );
  final featuredPath = featuredProjection('MAX(newest.file_path)');
  final singleCover = featuredProjection(
    "COALESCE(MAX(NULLIF(newest.cover_path, '')), '')",
    single: true,
  );
  final singlePath = featuredProjection('MAX(newest.file_path)', single: true);
  return (
    cover:
        '''COALESCE($featuredCover, $singleCover, (
          SELECT NULLIF(newest.cover_path, '')
          FROM $table c
          JOIN ${LibrarySchema.visibleView} newest ON newest.id = c.item_id
          WHERE c.field IN ($fields)
            AND c.name_key = $keyColumn
            AND NULLIF(newest.cover_path, '') IS NOT NULL
          ORDER BY newest.sort_added DESC LIMIT 1
        ))''',
    sample:
        '''COALESCE($featuredPath, $singlePath, (
          SELECT newest.file_path
          FROM $table c
          JOIN ${LibrarySchema.visibleView} newest ON newest.id = c.item_id
          WHERE c.field IN ($fields)
            AND c.name_key = $keyColumn
          ORDER BY newest.sort_added DESC LIMIT 1
        ))''',
  );
}
