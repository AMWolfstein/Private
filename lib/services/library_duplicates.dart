import 'package:sqflite/sqflite.dart';
import 'package:spotiflac_android/services/library_database_models.dart';
import 'package:spotiflac_android/services/library_schema.dart';
import 'package:spotiflac_android/utils/path_match_keys.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/duplicate_quality_policy.dart';

/// Review physical copies, not index rows, so duplicates are grouped by the
/// file on disk rather than by how it was indexed.
Future<List<IsrcDuplicateGroup>> readIsrcDuplicateGroups(
  DatabaseExecutor db,
) async {
  final rows = await db.rawQuery('''
    WITH merged AS (
      SELECT h.id, 'downloaded' AS source, h.track_name, h.artist_name,
             h.album_name, h.file_path, UPPER(TRIM(h.isrc)) AS isrc_key,
             h.bit_depth, h.sample_rate, h.bitrate, h.format, h.duration
      FROM history_db.history h
      WHERE h.isrc IS NOT NULL AND TRIM(h.isrc) != ''
      UNION ALL
      SELECT l.id, 'local' AS source, l.track_name, l.artist_name,
             l.album_name, l.file_path, UPPER(TRIM(l.isrc)) AS isrc_key,
             l.bit_depth, l.sample_rate, l.bitrate, l.format, l.duration
      FROM ${LibrarySchema.visibleView} l
      WHERE l.isrc IS NOT NULL AND TRIM(l.isrc) != ''
    )
    SELECT * FROM merged
    WHERE isrc_key IN (
      SELECT isrc_key FROM merged GROUP BY isrc_key HAVING COUNT(*) > 1
    )
    ORDER BY isrc_key, bit_depth DESC, sample_rate DESC, bitrate DESC, source, id
  ''');

  final groups = <String, List<IsrcDuplicateEntry>>{};
  final pathsByIsrc = <String, Set<String>>{};
  final identities = <String, String>{};
  final durationRanges = <String, (int, int)>{};
  final unsafeGroups = <String>{};
  final validIsrc = RegExp(r'^[A-Z]{2}[A-Z0-9]{3}\d{7}$');
  for (final row in rows) {
    final isrc = row['isrc_key'] as String? ?? '';
    final path = row['file_path'] as String? ?? '';
    if (!validIsrc.hasMatch(isrc) || path.isEmpty) continue;
    if (isCueBackedRow(path, row['format'] as String?)) continue;
    final title = (row['track_name'] as String? ?? '').trim().toLowerCase();
    final artist = (row['artist_name'] as String? ?? '').trim().toLowerCase();
    final duration = (row['duration'] as num?)?.toInt() ?? 0;
    final identity = '$title\u0000$artist';
    final previous = identities.putIfAbsent(isrc, () => identity);
    final range = durationRanges[isrc] ?? (duration, duration);
    final minimum = duration < range.$1 ? duration : range.$1;
    final maximum = duration > range.$2 ? duration : range.$2;
    durationRanges[isrc] = (minimum, maximum);
    // A reused ISRC is not proof of duplicate audio. Refuse destructive
    // cleanup for the entire group when recording identity is ambiguous.
    if (title.isEmpty ||
        artist.isEmpty ||
        duration <= 0 ||
        previous != identity ||
        maximum - minimum > 2) {
      unsafeGroups.add(isrc);
    }
    final keys = buildPhysicalPathMatchKeys(path);
    final seen = pathsByIsrc.putIfAbsent(isrc, () => {});
    final alreadySeen = keys.any(seen.contains);
    seen.addAll(keys);
    if (alreadySeen) continue;
    groups
        .putIfAbsent(isrc, () => [])
        .add(
          IsrcDuplicateEntry(
            id: row['id'] as String,
            source: row['source'] as String,
            trackName: row['track_name'] as String? ?? '',
            artistName: row['artist_name'] as String? ?? '',
            albumName: row['album_name'] as String? ?? '',
            filePath: path,
            bitDepth: (row['bit_depth'] as num?)?.toInt(),
            sampleRate: (row['sample_rate'] as num?)?.toInt(),
            bitrate: (row['bitrate'] as num?)?.toInt(),
            format: row['format'] as String?,
          ),
        );
  }
  return [
    for (final entry in groups.entries)
      if (entry.value.length > 1 &&
          !unsafeGroups.contains(entry.key) &&
          entry.value.every(hasComparableDuplicateQuality))
        IsrcDuplicateGroup(
          isrc: entry.key,
          entries: entry.value..sort(compareDuplicateQuality),
        ),
  ];
}
