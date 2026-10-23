import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:spotiflac_android/services/sqlite_helpers.dart' as sqlite;
import 'package:spotiflac_android/services/history_maintenance.dart';
import 'package:spotiflac_android/utils/isrc_utils.dart' as isrc;
import 'package:spotiflac_android/utils/ios_container_paths.dart';
import 'package:spotiflac_android/utils/logger.dart';
import 'package:spotiflac_android/utils/audio_format_utils.dart';

final _log = AppLogger('HistoryDatabase');

String? _currentContainerPath;

class HistoryDatabase {
  static String _normalizeSpotifyId(String? value) {
    return (value ?? '').trim().toLowerCase();
  }

  // The FTS table is a derived, optional index and is initialized lazily after
  // the existing schema migration. The background native writer shares
  // history.db and must accept the same schema contract and
  // user_version without depending on FTS5.
  static const int schemaVersion = 15;
  static const String searchFtsTable = 'history_search_fts';
  static final HistoryDatabase instance = HistoryDatabase._init();
  static final sqlite.SingleFlightInitializer<Database> _database =
      sqlite.SingleFlightInitializer<Database>();
  // null means this database connection has not attempted FTS setup yet.
  // false is a completed capability/setup result and must not be retried.
  bool? _searchFtsAvailable;

  HistoryDatabase._init();

  Future<Database> get database {
    return _database.getOrCreate(() async {
      final db = await sqlite.openAppDatabase(
        'history.db',
        version: schemaVersion,
        onCreate: _createDB,
        onUpgrade: _upgradeDB,
      );
      // onCreate normally initializes this derived index. Retry once after
      // opening an existing database in case an earlier setup was
      // interrupted; unsupported SQLite builds remain on the LIKE fallback.
      _searchFtsAvailable ??= await _createSearchFts(db);
      return db;
    });
  }

  bool get searchFtsAvailable => _searchFtsAvailable ?? false;

  Future<void> _createDB(Database db, int version) async {
    _log.i('Creating database schema v$version');

    await db.execute('''
      CREATE TABLE history (
        id TEXT PRIMARY KEY,
        track_name TEXT NOT NULL,
        artist_name TEXT NOT NULL,
        album_name TEXT NOT NULL,
        album_artist TEXT,
        cover_url TEXT,
        file_path TEXT NOT NULL,
        storage_mode TEXT,
        download_tree_uri TEXT,
        saf_relative_dir TEXT,
        saf_file_name TEXT,
        saf_repaired INTEGER,
        service TEXT NOT NULL,
        downloaded_at TEXT NOT NULL,
        isrc TEXT,
        spotify_id TEXT,
        track_number INTEGER,
        total_tracks INTEGER,
        disc_number INTEGER,
        total_discs INTEGER,
        duration INTEGER,
        release_date TEXT,
        quality TEXT,
        bit_depth INTEGER,
        sample_rate INTEGER,
        bitrate INTEGER,
        format TEXT,
        genre TEXT,
        composer TEXT,
        label TEXT,
        copyright TEXT,
        explicit INTEGER NOT NULL DEFAULT 0,
        has_lyrics INTEGER NOT NULL DEFAULT 0,
        lyrics_metadata_scan_version INTEGER NOT NULL DEFAULT 0,
        has_replaygain INTEGER NOT NULL DEFAULT 0,
        replaygain_metadata_scan_version INTEGER NOT NULL DEFAULT 0,
        spotify_id_norm TEXT,
        isrc_norm TEXT,
        match_key TEXT,
        album_key TEXT,
        search_text TEXT,
        sort_track TEXT,
        sort_artist TEXT,
        sort_album TEXT,
        sort_album_artist TEXT,
        sort_genre TEXT,
        sort_release TEXT,
        sort_added INTEGER
      )
    ''');

    await db.execute('CREATE INDEX idx_spotify_id ON history(spotify_id)');
    await db.execute('CREATE INDEX idx_isrc ON history(isrc)');
    await db.execute(
      'CREATE INDEX idx_downloaded_at ON history(downloaded_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_album ON history(album_name, album_artist)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_history_track_artist ON history(track_name, artist_name)',
    );
    await _createNormalizedIndexes(db);
    await _createQueueIndexes(db);
    await _createPathKeyTable(db);
    _searchFtsAvailable = await _createSearchFts(db);

    _log.i('Database schema created with indexes');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    _log.i('Upgrading database from v$oldVersion to v$newVersion');
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE history ADD COLUMN storage_mode TEXT');
      await db.execute('ALTER TABLE history ADD COLUMN download_tree_uri TEXT');
      await db.execute('ALTER TABLE history ADD COLUMN saf_relative_dir TEXT');
      await db.execute('ALTER TABLE history ADD COLUMN saf_file_name TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE history ADD COLUMN saf_repaired INTEGER');
    }
    if (oldVersion < 4) {
      final columns = await db.rawQuery('PRAGMA table_info(history)');
      final hasComposer = columns.any(
        (row) => (row['name']?.toString().toLowerCase() ?? '') == 'composer',
      );
      if (!hasComposer) {
        await db.execute('ALTER TABLE history ADD COLUMN composer TEXT');
      }
    }
    if (oldVersion < 5) {
      final columns = await db.rawQuery('PRAGMA table_info(history)');
      final hasTotalTracks = columns.any(
        (row) =>
            (row['name']?.toString().toLowerCase() ?? '') == 'total_tracks',
      );
      final hasTotalDiscs = columns.any(
        (row) => (row['name']?.toString().toLowerCase() ?? '') == 'total_discs',
      );
      if (!hasTotalTracks) {
        await db.execute('ALTER TABLE history ADD COLUMN total_tracks INTEGER');
      }
      if (!hasTotalDiscs) {
        await db.execute('ALTER TABLE history ADD COLUMN total_discs INTEGER');
      }
    }
    if (oldVersion < 6) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_history_track_artist ON history(track_name, artist_name)',
      );
    }
    if (oldVersion < 7) {
      await _createPathKeyTable(db);
    }
    if (oldVersion < 8) {
      await sqlite.addColumnIfMissing(db, 'history', 'spotify_id_norm', 'TEXT');
      await sqlite.addColumnIfMissing(db, 'history', 'isrc_norm', 'TEXT');
      await sqlite.addColumnIfMissing(db, 'history', 'match_key', 'TEXT');
    }
    if (oldVersion < 9) {
      await sqlite.addColumnIfMissing(db, 'history', 'bitrate', 'INTEGER');
      await sqlite.addColumnIfMissing(db, 'history', 'format', 'TEXT');
    }
    if (oldVersion < 10) {
      await sqlite.addColumnIfMissing(db, 'history', 'album_key', 'TEXT');
      await sqlite.addColumnIfMissing(db, 'history', 'search_text', 'TEXT');
      await _backfillNormalizedColumns(db);
      await _createNormalizedIndexes(db);
    }
    if (oldVersion < 11) {
      await sqlite.addColumnIfMissing(db, 'history', 'sort_track', 'TEXT');
      await sqlite.addColumnIfMissing(db, 'history', 'sort_artist', 'TEXT');
      await sqlite.addColumnIfMissing(db, 'history', 'sort_album', 'TEXT');
      await sqlite.addColumnIfMissing(
        db,
        'history',
        'sort_album_artist',
        'TEXT',
      );
      await sqlite.addColumnIfMissing(db, 'history', 'sort_genre', 'TEXT');
      await sqlite.addColumnIfMissing(db, 'history', 'sort_release', 'TEXT');
      await sqlite.addColumnIfMissing(db, 'history', 'sort_added', 'INTEGER');
      await _backfillQueueSortColumns(db);
      await _createQueueIndexes(db);
      _log.i('Added persisted queue sort columns');
    }
    if (oldVersion < 12) {
      await sqlite.addColumnIfMissing(
        db,
        'history',
        'explicit',
        'INTEGER NOT NULL DEFAULT 0',
      );
      _log.i('Added explicit-content metadata');
    }
    if (oldVersion < 13) {
      await sqlite.addColumnIfMissing(
        db,
        'history',
        'has_lyrics',
        'INTEGER NOT NULL DEFAULT 0',
      );
      await sqlite.addColumnIfMissing(
        db,
        'history',
        'lyrics_metadata_scan_version',
        'INTEGER NOT NULL DEFAULT 0',
      );
      _log.i('Added indexed lyrics availability metadata');
    }
    if (oldVersion < 14) {
      await sqlite.addColumnIfMissing(
        db,
        'history',
        'has_replaygain',
        'INTEGER NOT NULL DEFAULT 0',
      );
      await sqlite.addColumnIfMissing(
        db,
        'history',
        'replaygain_metadata_scan_version',
        'INTEGER NOT NULL DEFAULT 0',
      );
      _log.i('Added indexed ReplayGain availability metadata');
    }
    if (oldVersion < 15) {
      await sqlite.backfillPathKeys(db, 'history', 'history_path_keys');
      _log.i('Updated history path keys with provider document identities');
    }
  }

  Future<bool> _createSearchFts(DatabaseExecutor db) {
    return sqlite.createTrigramFtsIndex(
      db,
      ftsTable: searchFtsTable,
      contentTable: 'history',
      triggerPrefix: 'history_search_fts',
    );
  }

  static String normalizeLookupText(String? value) =>
      sqlite.normalizeLookupText(value);

  static String normalizeIsrc(String? value) => isrc.normalizeIsrc(value);

  static String matchKeyFor(String? trackName, String? artistName) {
    final track = normalizeLookupText(trackName);
    if (track.isEmpty) return '';
    return '$track|${normalizeLookupText(artistName)}';
  }

  Future<void> _createNormalizedIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_history_spotify_id_norm ON history(spotify_id_norm)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_history_isrc_norm ON history(isrc_norm)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_history_match_key ON history(match_key)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_history_album_key ON history(album_key)',
    );
  }

  Future<void> _createQueueIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_history_queue_added ON history(sort_added DESC, sort_track, id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_history_queue_track ON history(sort_track, sort_artist, id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_history_queue_artist ON history(sort_artist, sort_track, id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_history_queue_album ON history(sort_album, sort_track, id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_history_queue_genre ON history(sort_genre, sort_track, id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_history_queue_release ON history(sort_release, sort_track, id)',
    );
  }

  Future<void> _backfillNormalizedColumns(Database db) async {
    final rows = await db.query(
      'history',
      columns: [
        'id',
        'spotify_id',
        'isrc',
        'track_name',
        'artist_name',
        'album_name',
        'album_artist',
      ],
    );
    final batch = db.batch();
    for (final row in rows) {
      batch.update(
        'history',
        _normalizedColumns(
          spotifyId: row['spotify_id'] as String?,
          isrc: row['isrc'] as String?,
          trackName: row['track_name'] as String?,
          artistName: row['artist_name'] as String?,
          albumName: row['album_name'] as String?,
          albumArtist: row['album_artist'] as String?,
        ),
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    await batch.commit(noResult: true);
  }

  Map<String, dynamic> _normalizedColumns({
    required String? spotifyId,
    required String? isrc,
    required String? trackName,
    required String? artistName,
    required String? albumName,
    required String? albumArtist,
  }) {
    final normalizedTrack = normalizeLookupText(trackName);
    final normalizedArtist = normalizeLookupText(artistName);
    final normalizedAlbum = normalizeLookupText(albumName);
    final normalizedAlbumArtist = normalizeLookupText(
      (albumArtist ?? '').trim().isEmpty ? artistName : albumArtist,
    );
    return {
      'spotify_id_norm': _normalizeSpotifyId(spotifyId),
      'isrc_norm': normalizeIsrc(isrc),
      'match_key': matchKeyFor(trackName, artistName),
      'album_key': '$normalizedAlbum|$normalizedAlbumArtist',
      'search_text': [
        normalizedTrack,
        normalizedArtist,
        normalizedAlbum,
        normalizedAlbumArtist,
      ].where((value) => value.isNotEmpty).join(' '),
    };
  }

  Map<String, dynamic> _queueSortColumns({
    required String? trackName,
    required String? artistName,
    required String? albumName,
    required String? albumArtist,
    required String? genre,
    required String? releaseDate,
    required Object? downloadedAt,
  }) {
    final parsedDownloadedAt = downloadedAt is DateTime
        ? downloadedAt
        : DateTime.tryParse(downloadedAt?.toString() ?? '');
    return {
      'sort_track': normalizeLookupText(trackName),
      'sort_artist': normalizeLookupText(artistName),
      'sort_album': normalizeLookupText(albumName),
      'sort_album_artist': normalizeLookupText(
        (albumArtist ?? '').trim().isEmpty ? artistName : albumArtist,
      ),
      'sort_genre': normalizeLookupText(genre),
      'sort_release': releaseDate?.trim() ?? '',
      'sort_added': parsedDownloadedAt?.millisecondsSinceEpoch ?? 0,
    };
  }

  Future<void> _backfillQueueSortColumns(Database db) async {
    final rows = await db.query(
      'history',
      columns: [
        'id',
        'track_name',
        'artist_name',
        'album_name',
        'album_artist',
        'genre',
        'release_date',
        'downloaded_at',
      ],
    );
    final batch = db.batch();
    for (final row in rows) {
      batch.update(
        'history',
        _queueSortColumns(
          trackName: row['track_name'] as String?,
          artistName: row['artist_name'] as String?,
          albumName: row['album_name'] as String?,
          albumArtist: row['album_artist'] as String?,
          genre: row['genre'] as String?,
          releaseDate: row['release_date'] as String?,
          downloadedAt: row['downloaded_at'],
        ),
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> _createPathKeyTable(DatabaseExecutor db) =>
      sqlite.createPathKeyTable(db, 'history_path_keys');

  void _putPathKeysInBatch(Batch batch, String id, String? filePath) =>
      sqlite.putPathKeysInBatch(batch, 'history_path_keys', id, filePath);

  String _normalizeIosPath(String? filePath) {
    if (filePath == null || filePath.isEmpty) return filePath ?? '';
    if (!Platform.isIOS || _currentContainerPath == null) return filePath;

    return rebaseIosSandboxPath(filePath, '$_currentContainerPath/Documents');
  }

  Map<String, dynamic> _jsonToDbRow(Map<String, dynamic> json) {
    final downloadedAt = json['downloadedAt'];
    final parsedDownloadedAt = downloadedAt is DateTime
        ? downloadedAt
        : DateTime.tryParse(downloadedAt?.toString() ?? '');
    final row = {
      'id': json['id'],
      'track_name': json['trackName'],
      'artist_name': json['artistName'],
      'album_name': json['albumName'],
      'album_artist': json['albumArtist'],
      'cover_url': json['coverUrl'],
      'file_path': json['filePath'],
      'storage_mode': json['storageMode'],
      'download_tree_uri': json['downloadTreeUri'],
      'saf_relative_dir': json['safRelativeDir'],
      'saf_file_name': json['safFileName'],
      'saf_repaired': json['safRepaired'] == true ? 1 : 0,
      'service': json['service'],
      'downloaded_at':
          parsedDownloadedAt?.toUtc().toIso8601String() ??
          downloadedAt?.toString(),
      'isrc': json['isrc'],
      'spotify_id': json['spotifyId'],
      'track_number': json['trackNumber'],
      'total_tracks': json['totalTracks'],
      'disc_number': json['discNumber'],
      'total_discs': json['totalDiscs'],
      'duration': json['duration'],
      'release_date': json['releaseDate'],
      'quality': json['quality'],
      'bit_depth': json['bitDepth'],
      'sample_rate': json['sampleRate'],
      'bitrate': json['bitrate'],
      'format': json['format'],
      'genre': json['genre'],
      'composer': json['composer'],
      'label': json['label'],
      'copyright': json['copyright'],
      'explicit': json['explicit'] == true ? 1 : 0,
      'has_lyrics': json['hasLyrics'] == true ? 1 : 0,
      'lyrics_metadata_scan_version':
          (json['lyricsMetadataScanVersion'] as num?)?.toInt() ??
          (json.containsKey('hasLyrics') ? 1 : 0),
      'has_replaygain': metadataHasReplayGain(json) ? 1 : 0,
      'replaygain_metadata_scan_version':
          (json['replayGainMetadataScanVersion'] as num?)?.toInt() ?? 0,
    };
    row.addAll(
      _queueSortColumns(
        trackName: json['trackName'] as String?,
        artistName: json['artistName'] as String?,
        albumName: json['albumName'] as String?,
        albumArtist: json['albumArtist'] as String?,
        genre: json['genre'] as String?,
        releaseDate: json['releaseDate'] as String?,
        downloadedAt: parsedDownloadedAt,
      ),
    );
    row.addAll(
      _normalizedColumns(
        spotifyId: json['spotifyId'] as String?,
        isrc: json['isrc'] as String?,
        trackName: json['trackName'] as String?,
        artistName: json['artistName'] as String?,
        albumName: json['albumName'] as String?,
        albumArtist: json['albumArtist'] as String?,
      ),
    );
    return row;
  }

  Map<String, dynamic> _dbRowToJson(Map<String, dynamic> row) {
    return {
      'id': row['id'],
      'trackName': row['track_name'],
      'artistName': row['artist_name'],
      'albumName': row['album_name'],
      'albumArtist': row['album_artist'],
      'coverUrl': row['cover_url'],
      'filePath': _normalizeIosPath(row['file_path'] as String?),
      'storageMode': row['storage_mode'],
      'downloadTreeUri': row['download_tree_uri'],
      'safRelativeDir': row['saf_relative_dir'],
      'safFileName': row['saf_file_name'],
      'safRepaired': row['saf_repaired'] == 1 || row['saf_repaired'] == true,
      'service': row['service'],
      'downloadedAt': row['downloaded_at'],
      'isrc': row['isrc'],
      'spotifyId': row['spotify_id'],
      'trackNumber': row['track_number'],
      'totalTracks': row['total_tracks'],
      'discNumber': row['disc_number'],
      'totalDiscs': row['total_discs'],
      'duration': row['duration'],
      'releaseDate': row['release_date'],
      'quality': row['quality'],
      'bitDepth': row['bit_depth'],
      'sampleRate': row['sample_rate'],
      'bitrate': row['bitrate'],
      'format': row['format'],
      'genre': row['genre'],
      'composer': row['composer'],
      'label': row['label'],
      'copyright': row['copyright'],
      'explicit': row['explicit'] == 1 || row['explicit'] == true,
      'hasLyrics': row['has_lyrics'] == 1 || row['has_lyrics'] == true,
      'lyricsMetadataScanVersion': row['lyrics_metadata_scan_version'] ?? 0,
      'hasReplayGain':
          row['has_replaygain'] == 1 || row['has_replaygain'] == true,
      'replayGainMetadataScanVersion':
          row['replaygain_metadata_scan_version'] ?? 0,
    };
  }

  Future<void> replaceAll(Stream<Map<String, dynamic>> items) async {
    await replaceHistoryRows(await database, items.map(_jsonToDbRow));
  }

  Future<void> upsertBatch(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final json in items) {
        batch.insert(
          'history',
          _jsonToDbRow(json),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        _putPathKeysInBatch(
          batch,
          json['id'] as String,
          json['filePath'] as String?,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, dynamic>>> getAll({int? limit, int? offset}) async {
    final db = await database;
    final rows = await db.query(
      'history',
      orderBy: 'sort_added DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_dbRowToJson).toList();
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('history_path_keys');
      await txn.delete('history');
    });
    // Return freed pages to the OS (no-op unless the file was created with
    // auto_vacuum enabled).
    try {
      await db.execute('PRAGMA incremental_vacuum');
    } catch (_) {}
    _log.i('Cleared all history');
  }
}
