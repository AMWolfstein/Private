import 'package:sqflite/sqflite.dart';
import 'package:sistrum/services/library/browse/album_completeness.dart';
import 'package:sistrum/services/library/database/library_database_models.dart';
import 'package:sistrum/services/library/database/library_schema.dart';
import 'package:sistrum/services/library/browse/library_tag_credits.dart';
import 'package:sistrum/services/library/browse/library_browse_filters.dart';
import 'package:sistrum/services/library/browse/library_browse_order.dart';
import 'package:sistrum/services/library/browse/library_browse_rows.dart';
import 'package:sistrum/services/library/database/library_row_mapper.dart';
import 'package:sistrum/services/library/database/sqlite_helpers.dart'
    as sqlite;

/// Queue reads against an already opened local library.
class LibraryBrowseStore {
  final Database _db;
  final bool localFts;

  const LibraryBrowseStore(this._db, {required this.localFts});

  Future<List<Map<String, dynamic>>> localAlbumTracks(
    String albumName,
    String artistName,
  ) => localAlbumTracksByKey(
    '${sqlite.normalizeLookupText(albumName)}|${sqlite.normalizeLookupText(artistName)}',
  );

  Future<List<Map<String, dynamic>>> localAlbumTracksByKey(
    String albumKey,
  ) async {
    final rows = await _db.query(
      LibrarySchema.visibleView,
      where: 'album_key = ?',
      whereArgs: [albumKey],
      orderBy:
          'COALESCE(disc_number, 0), COALESCE(track_number, 0), track_name',
    );
    return rows.map(LibraryRowMapper.decode).toList(growable: false);
  }

  /// Brings the credits table up to date when a query filters by artist. A
  /// query without a scope builds a private one, which is correct but slower.
  Future<void> _ensureCredits(
    LibraryBrowseDbQuery request, {
    bool always = false,
  }) async {
    if (!always && request.albumArtist == null) return;
    await (request.credits ?? privateTagCreditScope()).ensure(_db);
  }

  Future<LibraryBrowseDbPage> trackPage(LibraryBrowseDbQuery request) async {
    await _ensureCredits(request);
    final args = <Object?>[];
    final orderTerms = queueTrackOrderTerms(request.sortMode);
    final usesCursor =
        request.cursor != null &&
        request.cursor!.values.length == orderTerms.length;
    final querySql = _queueTrackSql(
      request,
      args,
      orderTerms: orderTerms,
      usesCursor: usesCursor,
    );
    final rows = await _db.rawQuery(
      '''
      SELECT *
      FROM ($querySql)
      ORDER BY ${queueOrderBy(orderTerms)}
      LIMIT ? ${usesCursor ? '' : 'OFFSET ?'}
      ''',
      [...args, request.limit, if (!usesCursor) request.offset],
    );
    return LibraryBrowseDbPage(
      rows: rows.map(queueTrackRowToJson).toList(growable: false),
      nextCursor: queueCursorFromRow(rows.lastOrNull, orderTerms),
    );
  }

  Future<LibraryBrowseCounts> counts(LibraryBrowseDbQuery request) async {
    await _ensureCredits(request);
    final fastCounts = await _getUnfilteredQueueCounts(request);
    if (fastCounts != null) return fastCounts;
    final args = <Object?>[];
    final where = <String>[];
    _appendBrowseLocalFilters(where, args, request);
    final rows = await _db.rawQuery('''
        SELECT
          COUNT(*) AS all_count,
          COUNT(DISTINCT CASE WHEN ${isAlbumCompletenessFilter(request.metadata) ? '1' : 'grouped.album_total_tracks != 1'} THEN l.album_key END) AS album_count,
          COALESCE(SUM(CASE WHEN grouped.album_total_tracks = 1 THEN 1 ELSE 0 END), 0) AS single_count
        FROM ${LibrarySchema.visibleView} l
        JOIN (
          SELECT album_key, MAX(COALESCE(total_tracks, 0)) AS album_total_tracks
          FROM ${LibrarySchema.visibleView} candidate
          GROUP BY album_key
        ) grouped ON grouped.album_key = l.album_key
        ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ''', args);
    final row = rows.isNotEmpty ? rows.first : const <String, Object?>{};

    return LibraryBrowseCounts(
      allTrackCount: (row['all_count'] as num?)?.toInt() ?? 0,
      albumCount: (row['album_count'] as num?)?.toInt() ?? 0,
      singleTrackCount: (row['single_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// The default Library badges do not need a row-by-row join against album
  /// counts. Aggregate the covering album-key indexes directly and reserve the
  /// more expensive filtered query for active search/quality/metadata filters.
  Future<LibraryBrowseCounts?> _getUnfilteredQueueCounts(
    LibraryBrowseDbQuery request,
  ) async {
    if (sqlite.normalizeLookupText(request.searchQuery).isNotEmpty ||
        request.albumArtist != null ||
        request.quality != null ||
        request.format != null ||
        request.metadata != null) {
      return null;
    }

    final rows = await _db.rawQuery('''
      SELECT
        COALESCE(SUM(track_count), 0) AS all_count,
        COALESCE(SUM(CASE WHEN album_total_tracks != 1 THEN 1 ELSE 0 END), 0) AS album_count,
        COALESCE(SUM(CASE WHEN album_total_tracks = 1 THEN track_count ELSE 0 END), 0) AS single_count
      FROM (
        SELECT l.album_key, COUNT(*) AS track_count,
          MAX(COALESCE(l.total_tracks, 0)) AS album_total_tracks
        FROM ${LibrarySchema.visibleView} l
        GROUP BY l.album_key
      )
    ''');
    final row = rows.isEmpty ? const <String, Object?>{} : rows.first;
    return LibraryBrowseCounts(
      allTrackCount: (row['all_count'] as num?)?.toInt() ?? 0,
      albumCount: (row['album_count'] as num?)?.toInt() ?? 0,
      singleTrackCount: (row['single_count'] as num?)?.toInt() ?? 0,
    );
  }

  Future<LibraryBrowseDbPage> albumPage(LibraryBrowseDbQuery request) async {
    await _ensureCredits(request);
    final args = <Object?>[];
    final orderTerms = queueAlbumOrderTerms(request.sortMode);
    final usesCursor =
        request.cursor != null &&
        request.cursor!.values.length == orderTerms.length;
    final querySql = _queueAlbumSql(
      request,
      args,
      orderTerms: orderTerms,
      usesCursor: usesCursor,
    );
    final rows = await _db.rawQuery(
      '''
      SELECT *
      FROM ($querySql)
      ORDER BY ${queueOrderBy(orderTerms)}
      LIMIT ? ${usesCursor ? '' : 'OFFSET ?'}
      ''',
      [...args, request.limit, if (!usesCursor) request.offset],
    );
    return LibraryBrowseDbPage(
      rows: rows.toList(growable: false),
      nextCursor: queueCursorFromRow(rows.lastOrNull, orderTerms),
    );
  }

  /// Artists from the credits table: album artists and track artists alike,
  /// so a featured artist has a page. The cover and sample come from the newest
  /// song credited to the artist.
  Future<List<Map<String, dynamic>>> artistPage(
    LibraryBrowseDbQuery request,
  ) async {
    await _ensureCredits(request, always: true);
    final search = sqlite.normalizeSearchText(request.searchQuery);
    const table = LibraryTagCreditsCache.tempTable;
    final args = <Object?>[
      if (search.isNotEmpty) '%${escapeLikePattern(search)}%',
      request.limit,
      request.offset,
    ];
    return _db.rawQuery('''
      SELECT g.artist_key, g.artist_name, NULL AS cover_url,
        (
          SELECT NULLIF(newest.cover_path, '')
          FROM $table c
          JOIN ${LibrarySchema.visibleView} newest ON newest.id = c.item_id
          WHERE c.field IN ('album_artist', 'artist')
            AND c.name_key = g.artist_key
            AND NULLIF(newest.cover_path, '') IS NOT NULL
          ORDER BY newest.sort_added DESC LIMIT 1
        ) AS cover_path,
        (
          SELECT newest.file_path
          FROM $table c
          JOIN ${LibrarySchema.visibleView} newest ON newest.id = c.item_id
          WHERE c.field IN ('album_artist', 'artist')
            AND c.name_key = g.artist_key
          ORDER BY newest.sort_added DESC LIMIT 1
        ) AS sample_file_path,
        g.track_count
      FROM (
        SELECT name_key AS artist_key, MIN(name) AS artist_name,
          COUNT(DISTINCT item_id) AS track_count
        FROM $table
        WHERE field IN ('album_artist', 'artist') AND name_key != ''
          ${search.isEmpty ? '' : "AND name_key LIKE ? ESCAPE '\\'"}
        GROUP BY name_key
        ORDER BY name_key
        LIMIT ? OFFSET ?
      ) g
      ORDER BY g.artist_key
    ''', args);
  }

  String _queueTrackSql(
    LibraryBrowseDbQuery request,
    List<Object?> args, {
    required List<QueueOrderTerm> orderTerms,
    required bool usesCursor,
  }) {
    final where = <String>[];
    _appendBrowseLocalFilters(where, args, request);
    if (request.filterMode == 'singles') {
      where.add('''
          l.album_key IN (
            SELECT album_key
            FROM ${LibrarySchema.visibleView} candidate
            GROUP BY album_key
            HAVING MAX(COALESCE(total_tracks, 0)) = 1
          )
          ''');
    }
    final selectSql =
        '''
        SELECT
          'local' AS queue_source,
          'local_' || l.id AS unified_id,
          l.id,
          l.source_id,
          l.explicit,
          l.track_name,
          l.artist_name,
          l.album_name,
          l.album_artist,
          NULL AS cover_url,
          l.file_path,
          l.isrc,
          l.track_number,
          l.total_tracks,
          l.disc_number,
          l.total_discs,
          l.duration,
          l.release_date,
          NULL AS quality,
          l.bit_depth,
          l.sample_rate,
          l.genre,
          l.composer,
          l.label,
          l.copyright,
          l.cover_path,
          l.scanned_at,
          l.file_mod_time,
          l.bitrate,
          l.format,
          l.has_replaygain,
          l.has_lyrics,
          CASE WHEN l.audio_metadata_scan_version >= $libraryAudioMetadataScanVersion
            THEN 1 ELSE 0 END AS replaygain_metadata_scan_version,
          l.track_name_norm AS sort_track,
          l.artist_name_norm AS sort_artist,
          l.album_name_norm AS sort_album,
          l.sort_genre,
          l.sort_release,
          l.sort_added
          ${trackSizeColumns(request.sortMode)}
        FROM ${LibrarySchema.visibleView} l
        ${sizeJoin(request.sortMode, 'l')}
        ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
        ''';
    return _boundedQueuePart(
      selectSql,
      request,
      args,
      orderTerms,
      usesCursor: usesCursor,
    );
  }

  String _queueAlbumSql(
    LibraryBrowseDbQuery request,
    List<Object?> args, {
    required List<QueueOrderTerm> orderTerms,
    required bool usesCursor,
  }) {
    final unfiltered =
        sqlite.normalizeLookupText(request.searchQuery).isEmpty &&
        request.albumArtist == null &&
        request.quality == null &&
        request.format == null &&
        request.metadata == null;
    final releaseDatedOnly = request.sortMode == 'release-date-newest';
    final releaseOrder =
        (releaseDatedOnly || request.sortMode == 'artist-releases-newest')
        ? metadataReleaseDateSql('l.release_date')
        : "COALESCE(l.release_date, '')";
    final assessesCompleteness = isAlbumCompletenessFilter(request.metadata);
    final includeSingles =
        request.includeSingleTrackAlbums || assessesCompleteness;
    final completenessSql = assessesCompleteness
        ? albumCompletenessSql(localAlbumInventorySql())
        : null;
    final completenessColumns = assessesCompleteness
        ? 'ac.album_completeness, ac.album_present_tracks, ac.album_expected_tracks,'
        : 'NULL AS album_completeness, NULL AS album_present_tracks, NULL AS album_expected_tracks,';
    final albumKey = unfiltered ? 'l.album_key' : 'c.album_key';
    final where = <String>[];
    _appendBrowseLocalFilters(
      where,
      args,
      request,
      hasCompletenessJoin: assessesCompleteness,
    );
    final selectSql =
        '''
        SELECT
          'local' AS queue_source,
          $albumKey AS album_key,
          MIN(l.album_name) AS album_name,
          COALESCE(NULLIF(MIN(l.album_artist), ''), MIN(l.artist_name)) AS artist_name,
          NULL AS cover_url,
          MAX(CASE WHEN l.cover_path IS NOT NULL AND l.cover_path != '' THEN l.cover_path END) AS cover_path,
          MAX(l.file_path) AS sample_file_path,
          COUNT(*) AS track_count,
          MAX(CASE WHEN l.total_tracks > 0 THEN l.total_tracks END) AS album_total_tracks,
          MAX(CASE WHEN l.total_discs > 0 THEN l.total_discs END) AS album_total_discs,
          $completenessColumns
          ${unfiltered ? 'MAX(COALESCE(l.sort_added, 0))' : 'c.latest_added'} AS sort_added,
          MIN(l.album_name_norm) AS sort_album,
          MIN(l.album_artist_norm) AS sort_artist,
          ${releaseDatedOnly ? "SUBSTR(MAX(CASE WHEN $releaseOrder != '' THEN $releaseOrder || TRIM(l.release_date) END), 11) AS metadata_release_date," : ''}
          COALESCE(MAX($releaseOrder), '') AS sort_release,
          COALESCE(MAX(l.sort_genre), '') AS sort_genre
          ${albumSizeColumns(request.sortMode)}
        FROM ${LibrarySchema.visibleView} l
        ${sizeJoin(request.sortMode, 'l')}
        ${unfiltered ? '' : '''JOIN (
          SELECT
            album_key,
            COUNT(*) AS track_count,
            MAX(COALESCE(sort_added, 0)) AS latest_added
          FROM ${LibrarySchema.visibleView} candidate
          GROUP BY album_key
          ${includeSingles ? '' : 'HAVING MAX(COALESCE(total_tracks, 0)) != 1'}
        ) c ON c.album_key = l.album_key'''}
        ${assessesCompleteness ? 'JOIN ($completenessSql) ac ON ac.album_key = l.album_key' : ''}
        ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
        GROUP BY $albumKey
        ${unfiltered ? 'HAVING $albumKey IS NOT NULL ${includeSingles ? '' : 'AND MAX(COALESCE(l.total_tracks, 0)) != 1'}' : 'HAVING 1'}
        ${releaseDatedOnly ? "AND MAX($releaseOrder) != ''" : ''}
        ''';
    return _boundedQueuePart(
      selectSql,
      request,
      args,
      orderTerms,
      usesCursor: usesCursor,
    );
  }

  void _appendBrowseLocalFilters(
    List<String> where,
    List<Object?> args,
    LibraryBrowseDbQuery request, {
    bool hasCompletenessJoin = false,
  }) {
    appendAlbumCompletenessFilter(
      where,
      request,
      albumKey: 'l.album_key',
      hasJoin: hasCompletenessJoin,
    );
    if (request.albumArtist != null) {
      final key = sqlite.normalizeSearchText(request.albumArtist);
      const table = LibraryTagCreditsCache.tempTable;
      switch (request.artistCredit ?? LibraryArtistCredit.anyCredit) {
        case LibraryArtistCredit.albumArtist:
          where.add(
            "l.id IN (SELECT item_id FROM $table "
            "WHERE field = 'album_artist' AND name_key = ?)",
          );
          args.add(key);
        case LibraryArtistCredit.anyCredit:
          where.add(
            "l.id IN (SELECT item_id FROM $table "
            "WHERE field IN ('album_artist', 'artist') AND name_key = ?)",
          );
          args.add(key);
        case LibraryArtistCredit.appearsOn:
          // Only track credits, and no track of the release credits the artist
          // as album artist: the release belongs to someone else.
          where.add(
            "l.id IN (SELECT item_id FROM $table "
            "WHERE field = 'artist' AND name_key = ?)",
          );
          where.add(
            'l.album_key NOT IN (SELECT owner.album_key '
            'FROM ${LibrarySchema.visibleView} owner '
            "JOIN $table owned ON owned.item_id = owner.id "
            "WHERE owned.field = 'album_artist' AND owned.name_key = ?)",
          );
          args.add(key);
          args.add(key);
      }
    }
    final query = sqlite.normalizeSearchText(request.searchQuery);
    if (query.isNotEmpty) {
      final ftsQuery = sqlite.ftsPhraseSearchQuery(query);
      if (localFts && ftsQuery != null) {
        where.add('''
          l.id IN (
            SELECT id FROM library WHERE rowid IN (
              SELECT rowid
              FROM library_search_fts
              WHERE library_search_fts MATCH ?
            )
          )
          ''');
        args.add(ftsQuery);
      } else {
        final like = '%${escapeLikePattern(query)}%';
        where.add("l.search_text LIKE ? ESCAPE '\\'");
        args.add(like);
      }
    }
    appendQueueCommonFilters(
      where,
      args,
      request,
      filePathExpr: 'l.file_path',
      formatExpr: 'l.format',
      qualityExpr: 'NULL',
      bitDepthExpr: 'l.bit_depth',
      artistExpr: 'l.artist_name',
      albumArtistExpr: 'l.album_artist',
      releaseDateExpr: 'l.release_date',
      genreExpr: 'l.genre',
      trackNumberExpr: 'l.track_number',
      discNumberExpr: 'l.disc_number',
      isrcExpr: 'l.isrc',
      labelExpr: 'l.label',
      hasLyricsExpr: 'l.has_lyrics',
      lyricsKnownExpr:
          'COALESCE(l.audio_metadata_scan_version, 0) >= $libraryLyricsMetadataScanVersion',
      hasReplayGainExpr: 'l.has_replaygain',
    );
  }

  String _boundedQueuePart(
    String selectSql,
    LibraryBrowseDbQuery request,
    List<Object?> args,
    List<QueueOrderTerm> orderTerms, {
    required bool usesCursor,
  }) {
    final cursorPredicate = usesCursor
        ? queueCursorPredicate(request.cursor, orderTerms, args)
        : '';
    final branchLimit = usesCursor
        ? request.limit
        : request.limit + request.offset;
    args.add(branchLimit);
    final branchOrder = orderTerms
        .where((term) => term.column != 'queue_source')
        .toList(growable: false);
    return '''
      SELECT * FROM (
        SELECT *
        FROM ($selectSql)
        ${cursorPredicate.isEmpty ? '' : 'WHERE $cursorPredicate'}
        ORDER BY ${queueOrderBy(branchOrder)}
        LIMIT ?
      )
    ''';
  }
}
