import 'package:sistrum/services/library/library_database_models.dart';
import 'package:sistrum/services/library/library_file_sizes.dart';

class QueueOrderTerm {
  final String column;
  final bool descending;

  const QueueOrderTerm(this.column, {this.descending = false});
}

String sizeJoin(String sortMode, String alias) => isLibrarySizeSort(sortMode)
    ? 'LEFT JOIN track_file_sizes file_sizes ON file_sizes.item_id = $alias.id'
    : '';

String trackSizeColumns(String sortMode) => isLibrarySizeSort(sortMode)
    ? ', file_sizes.size_bytes AS file_size_bytes, '
          '(file_sizes.size_bytes IS NULL) AS sort_size_unknown, '
          'COALESCE(file_sizes.size_bytes, 0) AS sort_size'
    : '';

String albumSizeColumns(String sortMode) => isLibrarySizeSort(sortMode)
    ? ', (COUNT(file_sizes.size_bytes) < COUNT(*)) AS sort_size_unknown, '
          'COALESCE(SUM(file_sizes.size_bytes), 0) AS sort_size'
    : '';

List<QueueOrderTerm> queueTrackOrderTerms(String sortMode) {
  return switch (sortMode) {
    'size-asc' || 'size-desc' => [
      const QueueOrderTerm('sort_size_unknown'),
      QueueOrderTerm('sort_size', descending: sortMode == 'size-desc'),
      const QueueOrderTerm('sort_track'),
      const QueueOrderTerm('id'),
    ],
    'oldest' => const [
      QueueOrderTerm('sort_added'),
      QueueOrderTerm('sort_track'),
      QueueOrderTerm('id'),
    ],
    'a-z' => const [
      QueueOrderTerm('sort_track'),
      QueueOrderTerm('sort_artist'),
      QueueOrderTerm('id'),
    ],
    'z-a' => const [
      QueueOrderTerm('sort_track', descending: true),
      QueueOrderTerm('sort_artist', descending: true),
      QueueOrderTerm('id'),
    ],
    'artist-asc' => const [
      QueueOrderTerm('sort_artist'),
      QueueOrderTerm('sort_track'),
      QueueOrderTerm('id'),
    ],
    'artist-desc' => const [
      QueueOrderTerm('sort_artist', descending: true),
      QueueOrderTerm('sort_track'),
      QueueOrderTerm('id'),
    ],
    'album-asc' => const [
      QueueOrderTerm('sort_album'),
      QueueOrderTerm('sort_track'),
      QueueOrderTerm('id'),
    ],
    'album-desc' => const [
      QueueOrderTerm('sort_album', descending: true),
      QueueOrderTerm('sort_track'),
      QueueOrderTerm('id'),
    ],
    'release-oldest' => const [
      QueueOrderTerm('sort_release'),
      QueueOrderTerm('sort_track'),
      QueueOrderTerm('id'),
    ],
    'release-newest' => const [
      QueueOrderTerm('sort_release', descending: true),
      QueueOrderTerm('sort_track'),
      QueueOrderTerm('id'),
    ],
    'genre-asc' => const [
      QueueOrderTerm('sort_genre'),
      QueueOrderTerm('sort_track'),
      QueueOrderTerm('id'),
    ],
    'genre-desc' => const [
      QueueOrderTerm('sort_genre', descending: true),
      QueueOrderTerm('sort_track'),
      QueueOrderTerm('id'),
    ],
    _ => const [
      QueueOrderTerm('sort_added', descending: true),
      QueueOrderTerm('sort_track'),
      QueueOrderTerm('id'),
    ],
  };
}

List<QueueOrderTerm> queueAlbumOrderTerms(String sortMode) {
  return switch (sortMode) {
    'size-asc' || 'size-desc' => [
      const QueueOrderTerm('sort_size_unknown'),
      QueueOrderTerm('sort_size', descending: sortMode == 'size-desc'),
      const QueueOrderTerm('sort_album'),
      const QueueOrderTerm('album_key'),
    ],
    'release-date-newest' => const [
      QueueOrderTerm('sort_release', descending: true),
      QueueOrderTerm('album_key'),
    ],
    'artist-releases-newest' => const [
      QueueOrderTerm('sort_release', descending: true),
      QueueOrderTerm('sort_added', descending: true),
      QueueOrderTerm('album_key'),
    ],
    'oldest' => const [
      QueueOrderTerm('sort_added'),
      QueueOrderTerm('sort_album'),
      QueueOrderTerm('album_key'),
    ],
    'a-z' || 'album-asc' => const [
      QueueOrderTerm('sort_album'),
      QueueOrderTerm('sort_artist'),
      QueueOrderTerm('album_key'),
    ],
    'z-a' || 'album-desc' => const [
      QueueOrderTerm('sort_album', descending: true),
      QueueOrderTerm('sort_artist', descending: true),
      QueueOrderTerm('album_key'),
    ],
    'artist-asc' => const [
      QueueOrderTerm('sort_artist'),
      QueueOrderTerm('sort_album'),
      QueueOrderTerm('album_key'),
    ],
    'artist-desc' => const [
      QueueOrderTerm('sort_artist', descending: true),
      QueueOrderTerm('sort_album'),
      QueueOrderTerm('album_key'),
    ],
    'release-oldest' => const [
      QueueOrderTerm('sort_release'),
      QueueOrderTerm('sort_album'),
      QueueOrderTerm('album_key'),
    ],
    'release-newest' => const [
      QueueOrderTerm('sort_release', descending: true),
      QueueOrderTerm('sort_album'),
      QueueOrderTerm('album_key'),
    ],
    'genre-asc' => const [
      QueueOrderTerm('sort_genre'),
      QueueOrderTerm('sort_album'),
      QueueOrderTerm('album_key'),
    ],
    'genre-desc' => const [
      QueueOrderTerm('sort_genre', descending: true),
      QueueOrderTerm('sort_album'),
      QueueOrderTerm('album_key'),
    ],
    _ => const [
      QueueOrderTerm('sort_added', descending: true),
      QueueOrderTerm('sort_album'),
      QueueOrderTerm('album_key'),
    ],
  };
}

String queueOrderBy(List<QueueOrderTerm> terms) => terms
    .map((term) => '${term.column} ${term.descending ? 'DESC' : 'ASC'}')
    .join(', ');

String queueCursorPredicate(
  LibraryBrowseDbCursor? cursor,
  List<QueueOrderTerm> terms,
  List<Object?> args,
) {
  if (cursor == null || cursor.values.length != terms.length) return '';
  final clauses = <String>[];
  final first = terms.first;
  final coarseOperator = first.descending ? '<=' : '>=';
  args.add(cursor.values.first);
  for (var i = 0; i < terms.length; i++) {
    final comparisons = <String>[];
    for (var j = 0; j < i; j++) {
      comparisons.add('${terms[j].column} = ?');
      args.add(cursor.values[j]);
    }
    comparisons.add('${terms[i].column} ${terms[i].descending ? '<' : '>'} ?');
    args.add(cursor.values[i]);
    clauses.add('(${comparisons.join(' AND ')})');
  }
  return '(${first.column} $coarseOperator ?) AND (${clauses.join(' OR ')})';
}

LibraryBrowseDbCursor? queueCursorFromRow(
  Map<String, dynamic>? row,
  List<QueueOrderTerm> terms,
) {
  if (row == null) return null;
  final values = <Object>[];
  for (final term in terms) {
    final value = row[term.column];
    if (value is! Object) return null;
    values.add(value);
  }
  return LibraryBrowseDbCursor(List<Object>.unmodifiable(values));
}
