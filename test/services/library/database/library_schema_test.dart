import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/services/library/database/library_row_mapper.dart';
import 'package:sistrum/services/library/database/library_schema.dart';

import '../../../support/sqlite_process_database.dart';

Map<String, dynamic> _track(String id, {String isrc = 'same'}) =>
    LocalLibraryItem(
      id: id,
      trackName: ' Song ',
      artistName: 'ARTIST',
      albumName: 'Album',
      filePath: '/music/$id.flac',
      scannedAt: DateTime.utc(2026),
      isrc: isrc,
      trackNumber: 1,
      totalTracks: 2,
      hasLyrics: true,
      hasReplayGain: true,
    ).toJson();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SqliteProcessDatabase db;
  setUp(() async {
    db = await SqliteProcessDatabase.open();
    await db.execute('PRAGMA recursive_triggers = ON');
  });
  tearDown(() => db.close());

  Future<List<String>> lookupObjects() async => [
    for (final row in await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE name LIKE '%lookup%' ORDER BY name",
    ))
      row['name']! as String,
  ];

  test(
    'fresh schema has no lookup summary and keeps replace, move and delete behaviour',
    () async {
      await LibrarySchema.create(db, LibrarySchema.version);
      expect(await lookupObjects(), isEmpty);
      for (final id in ['a', 'b']) {
        await db.insert(
          'library',
          LibraryRowMapper.encode(_track(id)),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await db.insert(
        'library',
        LibraryRowMapper.encode(_track('a', isrc: 'new')),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      expect(await db.query('library'), hasLength(2));
      await db.insert('library_sources', {
        'id': 'nas',
        'path': '/storage/emulated/0/Music',
        'display_name': 'Music',
      });
      await db.update(
        'library',
        {'source_id': 'nas'},
        where: 'id = ?',
        whereArgs: ['a'],
      );
      expect((await db.query(LibrarySchema.visibleView)).length, 2);
      await db.update(
        'library_sources',
        {'available': 0},
        where: 'id = ?',
        whereArgs: ['nas'],
      );
      expect((await db.query(LibrarySchema.visibleView)).single['id'], 'b');
      await db.delete('library', where: 'id = ?', whereArgs: ['a']);
      expect((await db.query('library')).single['id'], 'b');
      await db.delete('library');
      expect(await db.query('library'), isEmpty);
    },
  );

  test('row mapping round-trips metadata and preserves unknown scan flags', () {
    final track = _track('full');
    expect(LibraryRowMapper.decode(LibraryRowMapper.encode(track)), track);
    final filename = LibraryRowMapper.encode({
      ...track,
      'sourceId': 'nas',
      'metadataFromFilename': true,
      'hasReplayGain': false,
    });
    expect(filename['source_id'], 'nas');
    expect(filename['audio_metadata_scan_version'], 0);
    expect(filename['has_replaygain'], 0);
    final tagged = LibraryRowMapper.encode({
      ...track,
      'hasReplayGain': false,
      'replaygain_track_gain': '-4.5 dB',
      'explicit': 1,
      'audioMetadataScanVersion': 3,
    });
    expect(tagged['has_replaygain'], 1);
    expect(tagged['audio_metadata_scan_version'], 3);
    expect(LibraryRowMapper.decode(tagged)['explicit'], true);
  });

  test(
    'schema v19 indexes album_artist_norm for artist pages (PERF-401)',
    () async {
      await LibrarySchema.create(db, LibrarySchema.version);
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' "
        "AND name='idx_library_album_artist_norm'",
      );
      expect(indexes, hasLength(1));
      final plan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT l.* FROM library_visible l '
        "WHERE l.album_artist_norm = 'artist' LIMIT 40",
      );
      final detail = plan.map((row) => row.values.join(' ')).join(' | ');
      expect(detail, contains('idx_library_album_artist_norm'));
    },
  );
}
