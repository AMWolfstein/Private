import 'package:sistrum/services/library/browse/album_completeness.dart';
import 'package:sistrum/services/library/database/library_database_models.dart';
import 'package:sistrum/utils/scan/library_format_filters.dart';

// SQL builders for the queue tab's local-library queries.

String confirmedMissingLyricsSqlPredicate({
  required String hasLyricsExpr,
  required String lyricsKnownExpr,
}) => '($lyricsKnownExpr) AND COALESCE($hasLyricsExpr, 0) = 0';

String missingReplayGainSqlPredicate({required String hasReplayGainExpr}) =>
    'COALESCE($hasReplayGainExpr, 0) = 0';

/// Normalize supported audio-tag dates for chronology, without consulting scan dates.
/// Accept year, year-month, ISO date/timestamp, slash dates and compact YYYYMMDD.
/// Invalid/undated tags have no release order and stay out of Latest Releases.
String metadataReleaseDateSql(String column) {
  final raw = "REPLACE(TRIM(COALESCE($column, '')), '/', '-')";
  final year = '[0-9][0-9][0-9][0-9]';
  final pair = '[0-9][0-9]';
  final candidate =
      """(CASE
    WHEN $raw GLOB '$year' THEN $raw || '-01-01'
    WHEN $raw GLOB '$year-$pair' THEN $raw || '-01'
    WHEN SUBSTR($raw,1,10) GLOB '$year-$pair-$pair' THEN SUBSTR($raw,1,10)
    WHEN $raw GLOB '$year$pair$pair' THEN
      SUBSTR($raw,1,4) || '-' || SUBSTR($raw,5,2) || '-' || SUBSTR($raw,7,2)
    ELSE NULL END)""";
  return "COALESCE(CASE WHEN STRFTIME('%Y-%m-%d', $candidate, '+0 days') = $candidate "
      "THEN $candidate END, '')";
}

/// Album inventory for completeness assessment over scanned local tracks.
/// Retained rows on disconnected sources still make the assessment unknown.
String localAlbumInventorySql() {
  return '''
    SELECT l.album_key, LOWER(TRIM(l.track_name)) AS title,
      l.track_number, l.total_tracks, l.disc_number, l.total_discs,
      CASE WHEN source.available = 0 THEN 1 ELSE 0 END AS unavailable
    FROM library l LEFT JOIN library_sources source ON source.id = l.source_id
    WHERE COALESCE(source.enabled, 1) = 1
  ''';
}

String escapeLikePattern(String value) {
  return value
      .replaceAll('\\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}

void appendAlbumCompletenessFilter(
  List<String> where,
  LibraryBrowseDbQuery request, {
  required String albumKey,
  required bool hasJoin,
}) {
  if (!isAlbumCompletenessFilter(request.metadata)) return;
  final status = request.metadata == incompleteAlbumFilter
      ? 'incomplete'
      : 'unknown';
  if (hasJoin) {
    where.add("ac.album_completeness = '$status'");
    return;
  }
  final assessment = albumCompletenessSql(localAlbumInventorySql());
  where.add(
    "$albumKey IN (SELECT album_key FROM ($assessment) WHERE album_completeness = '$status')",
  );
}

void appendQueueCommonFilters(
  List<String> where,
  List<Object?> args,
  LibraryBrowseDbQuery request, {
  required String filePathExpr,
  required String? formatExpr,
  required String qualityExpr,
  required String bitDepthExpr,
  required String artistExpr,
  required String albumArtistExpr,
  required String releaseDateExpr,
  required String genreExpr,
  required String trackNumberExpr,
  required String discNumberExpr,
  required String isrcExpr,
  required String labelExpr,
  required String hasLyricsExpr,
  required String lyricsKnownExpr,
  required String hasReplayGainExpr,
}) {
  final quality = request.quality?.trim().toLowerCase();
  if (quality != null && quality.isNotEmpty) {
    final isHiRes =
        '(COALESCE($bitDepthExpr, 0) >= 24 OR LOWER(COALESCE($qualityExpr, \'\')) LIKE \'24%\')';
    final isCd =
        '(COALESCE($bitDepthExpr, 0) = 16 OR LOWER(COALESCE($qualityExpr, \'\')) LIKE \'16%\')';
    switch (quality) {
      case LibraryQualityFilter.hiRes:
        where.add(isHiRes);
        break;
      case LibraryQualityFilter.cd:
        where.add(isCd);
        break;
      case LibraryQualityFilter.lossy:
        where.add('NOT ($isHiRes OR $isCd)');
        break;
    }
  }

  final format = request.format?.trim().toLowerCase();
  if (format != null && format.isNotEmpty) {
    final aliases = libraryFormatFilterAliases[format] ?? [format];
    final matches = <String>[];
    if (formatExpr != null) {
      matches.add(
        'LOWER(REPLACE(TRIM(COALESCE($formatExpr, \'\')), \'-\', \'_\')) '
        'IN (${List.filled(aliases.length, '?').join(', ')})',
      );
      args.addAll(aliases);
    }
    for (final alias in aliases) {
      matches.add("LOWER($filePathExpr) LIKE ? ESCAPE '\\'");
      args.add('%.${escapeLikePattern(alias)}');
    }
    where.add('(${matches.join(' OR ')})');
  }

  final metadata = request.metadata?.trim();
  if (metadata == null || metadata.isEmpty) return;
  final hasArtist = 'TRIM(COALESCE($artistExpr, \'\')) != \'\'';
  final hasAlbumArtist = 'TRIM(COALESCE($albumArtistExpr, \'\')) != \'\'';
  final hasReleaseDate =
      'TRIM(COALESCE($releaseDateExpr, \'\')) GLOB \'*[0-9][0-9][0-9][0-9]*\'';
  final hasGenre = 'TRIM(COALESCE($genreExpr, \'\')) != \'\'';
  final hasTrackNumber = 'COALESCE($trackNumberExpr, 0) > 0';
  final hasDiscNumber = 'COALESCE($discNumberExpr, 0) > 0';
  final hasLabel = 'TRIM(COALESCE($labelExpr, \'\')) != \'\'';
  final normalizedIsrc =
      'REPLACE(REPLACE(UPPER(TRIM(COALESCE($isrcExpr, \'\'))), \'-\', \'\'), \' \', \'\')';
  final hasIncorrectIsrc =
      'TRIM(COALESCE($isrcExpr, \'\')) != \'\' AND LENGTH($normalizedIsrc) != 12';
  final isComplete =
      '($hasArtist AND $hasAlbumArtist AND $hasReleaseDate AND $hasGenre AND $hasTrackNumber AND $hasDiscNumber AND $hasLabel AND NOT ($hasIncorrectIsrc))';

  switch (metadata) {
    case 'complete':
      where.add(isComplete);
      break;
    case 'missing-any':
      where.add('NOT $isComplete');
      break;
    case 'missing-year':
      where.add('NOT ($hasReleaseDate)');
      break;
    case 'missing-genre':
      where.add('NOT ($hasGenre)');
      break;
    case 'missing-album-artist':
      where.add('NOT ($hasAlbumArtist)');
      break;
    case 'missing-track-number':
      where.add('NOT ($hasTrackNumber)');
      break;
    case 'missing-disc-number':
      where.add('NOT ($hasDiscNumber)');
      break;
    case 'missing-artist':
      where.add('NOT ($hasArtist)');
      break;
    case 'incorrect-isrc-format':
      where.add('($hasIncorrectIsrc)');
      break;
    case 'missing-isrc':
      where.add('TRIM(COALESCE($isrcExpr, \'\')) = \'\'');
      break;
    case 'missing-label':
      where.add('NOT ($hasLabel)');
      break;
    case 'missing-lyrics':
      // A default false value on legacy rows means "not scanned yet", not
      // "confirmed missing". Only show files whose lyrics probe completed.
      where.add(
        confirmedMissingLyricsSqlPredicate(
          hasLyricsExpr: hasLyricsExpr,
          lyricsKnownExpr: lyricsKnownExpr,
        ),
      );
      break;
    case 'has-replaygain':
      where.add('COALESCE($hasReplayGainExpr, 0) != 0');
      break;
    case 'missing-replaygain':
      // Include legacy rows without indexed ReplayGain as candidates until
      // a metadata refresh confirms their tags. Requiring a new scan version
      // hides the entire older collection before it has been rescanned.
      where.add(
        missingReplayGainSqlPredicate(hasReplayGainExpr: hasReplayGainExpr),
      );
      break;
  }
}
