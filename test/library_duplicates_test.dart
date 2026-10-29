import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/models/local_library_item.dart';
import 'package:sistrum/services/library/library_duplicates.dart';
import 'package:sistrum/services/library/library_schema.dart';

import 'support/sqlite_process_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SqliteProcessDatabase db;

  setUp(() async {
    db = await SqliteProcessDatabase.open();
    await LibrarySchema.create(db, LibrarySchema.version);
  });
  tearDown(() => db.close());

  Future<void> add(
    String id,
    String path, {
    String? sourceId,
    String isrc = 'USABC2600001',
    String title = 'Track',
    int duration = 180,
    String? format = 'flac',
    int? bitrate = 1000,
    int sampleRate = 44100,
  }) => db
      .insert('library', {
        'id': id,
        'track_name': title,
        'artist_name': 'Artist',
        'album_name': 'Album',
        'file_path': path,
        'isrc': isrc,
        'duration': duration,
        'format': format,
        'bitrate': bitrate,
        'bit_depth': 16,
        'sample_rate': sampleRate,
        'scanned_at': '2026-10-10',
        'source_id': sourceId ?? LocalLibraryItem.legacySourceId,
      })
      .then((_) {});

  test(
    'rescans and alternate SAF tree URIs do not duplicate one physical file',
    () async {
      const document = 'remote%3AAlbum%2FTrack.flac';
      await add('first', 'content://rsaf/tree/root/document/$document');
      await add('scan', 'content://rsaf/tree/album/document/$document');
      await add('third', 'content://rsaf/document/$document');
      expect(await readIsrcDuplicateGroups(db), isEmpty);
    },
  );

  test('actual copies and different formats remain selectable', () async {
    await add('first', '/music/Track.flac');
    await add('second', 'file:///music/Track.flac');
    await add('conversion', '/music/Track.opus');
    await add('copy', '/playlist/Track.flac');
    final group = (await readIsrcDuplicateGroups(db)).single;
    expect(group.entries.map((entry) => entry.filePath).toSet(), {
      '/music/Track.flac',
      '/music/Track.opus',
      '/playlist/Track.flac',
    });
  });

  for (final invalid in ['000000000000', 'SAME-RECORDING', 'USABC260000']) {
    test(
      'placeholder or malformed ISRC $invalid never authorizes cleanup',
      () async {
        await add('one', '/music/one.flac', isrc: invalid);
        await add('two', '/music/two.flac', isrc: invalid);
        expect(await readIsrcDuplicateGroups(db), isEmpty);
      },
    );
  }

  test(
    'reused ISRC with different titles or durations is not a duplicate group',
    () async {
      await add('one', '/music/one.flac');
      await add('two', '/music/two.flac', title: 'Different song');
      expect(await readIsrcDuplicateGroups(db), isEmpty);
      await db.update(
        'library',
        {'track_name': 'Track', 'duration': 183},
        where: 'id = ?',
        whereArgs: ['two'],
      );
      expect(await readIsrcDuplicateGroups(db), isEmpty);
      await db.update(
        'library',
        {'duration': 182},
        where: 'id = ?',
        whereArgs: ['two'],
      );
      expect((await readIsrcDuplicateGroups(db)).single.entries, hasLength(2));
      await db.update(
        'library',
        {'duration': null},
        where: 'id = ?',
        whereArgs: ['two'],
      );
      expect(await readIsrcDuplicateGroups(db), isEmpty);
    },
  );

  test('lossy copies rank by bitrate before sample rate', () async {
    await add(
      'high-rate',
      '/music/low.mp3',
      format: 'mp3',
      bitrate: 128,
      sampleRate: 48000,
    );
    await add('high-bitrate', '/music/high.mp3', format: 'mp3', bitrate: 320);
    final group = (await readIsrcDuplicateGroups(db)).single;
    expect(group.entries.first.id, 'high-bitrate');
  });

  test('legacy FLAC without format uses its unambiguous extension', () async {
    await add(
      'legacy',
      '/music/legacy.flac',
      format: null,
      bitrate: null,
      sampleRate: 96000,
    );
    await db.update(
      'library',
      {'bit_depth': 24},
      where: 'id = ?',
      whereArgs: ['legacy'],
    );
    await add('mp3', '/music/copy.mp3', format: 'mp3', bitrate: 320);
    expect(
      (await readIsrcDuplicateGroups(db)).single.entries.first.id,
      'legacy',
    );
  });

  test(
    'unknown fidelity or lossy bitrate cannot authorize keep-best',
    () async {
      await add('unknown', '/music/audio.m4a', format: null);
      await add('mp3', '/music/copy.mp3', format: 'mp3', bitrate: 320);
      expect(await readIsrcDuplicateGroups(db), isEmpty);
      await db.update(
        'library',
        {'format': 'mp3', 'bitrate': null},
        where: 'id = ?',
        whereArgs: ['unknown'],
      );
      expect(await readIsrcDuplicateGroups(db), isEmpty);
    },
  );
}
