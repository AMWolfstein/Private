import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sistrum/services/library/browse/library_tag_credits.dart';
import 'package:sistrum/services/library/covers/durable_cover_reference.dart';
import 'package:sistrum/services/playback/stats/listening_statistics.dart';
import 'package:sistrum/services/playback/stats/listening_rewind.dart';

void main() {
  late Database db;
  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE listening (day TEXT, track_key TEXT, title TEXT, artist TEXT, album TEXT, artwork TEXT, milliseconds INTEGER DEFAULT 0, plays INTEGER DEFAULT 0, PRIMARY KEY(day,track_key))',
    );
  });
  tearDown(() => db.close());
  Future<void> add(
    String day,
    String key,
    String artist, {
    String? cover,
    int time = 60000,
  }) => db
      .insert('listening', {
        'day': day,
        'track_key': key,
        'title': key,
        'artist': artist,
        'album': 'Album',
        'artwork': cover,
        'milliseconds': time,
        'plays': 1,
      })
      .then((_) {});

  test(
    'latest missing cover and Rewind first/replay recover the window cover',
    () async {
      await add('2026-01-01', 'a', 'Artist');
      await add(
        '2026-01-02',
        'a',
        'Artist',
        cover: '/data/files/library_covers/a.jpg',
      );
      await add('2026-01-03', 'a', 'Artist');
      await db.rawUpdate("UPDATE listening SET plays=3 WHERE day='2026-01-01'");
      final range = ListeningRewindRange.of(
        ListeningRewindPeriod.year,
        DateTime(2026, 6),
      );
      final rewind = await readListeningRewind(db, range, yearly: true);
      expect(
        rewind.summary.tracks.single.track.artwork,
        '/data/files/library_covers/a.jpg',
      );
      expect(
        rewind.year!.firstPlay!.track.artwork,
        '/data/files/library_covers/a.jpg',
      );
      expect(rewind.replay!.track.artwork, '/data/files/library_covers/a.jpg');
      expect(rewind.summary.milliseconds, 180000);
    },
  );

  test(
    'monthly leaders loyalty and discoveries respect custom credit rules',
    () async {
      const rules = TagCreditRules(
        artistDelimiters: [';', '/'],
        keepTogether: ['AC/DC'],
      );
      await add('2025-12-31', 'old', 'AC/DC; B');
      await add('2026-01-01', 'a', 'AC/DC; C', time: 180000);
      await add('2026-01-01', 'b', 'AC/DC', time: 120000);
      await add('2026-01-02', 'c', 'AC/DC; B');
      await add(
        '2026-01-03',
        'd',
        'ac/dc; b',
        cover: '/data/files/covers/duet.jpg',
      );
      final range = ListeningRewindRange.of(
        ListeningRewindPeriod.year,
        DateTime(2026, 6),
      );
      final rewind = await readListeningRewind(
        db,
        range,
        yearly: true,
        rules: rules,
      );
      expect(rewind.year!.monthlyTopArtists[1], 'AC/DC');
      expect(rewind.year!.loyalArtist, 'AC/DC');
      expect(rewind.year!.loyalArtistDays, 3);
      expect(rewind.summary.artistArtwork.keys, contains('AC/DC'));
      expect(rewind.summary.artistArtwork.keys, isNot(contains('ac/dc')));
      expect(rewind.newArtists, ['C']);
      expect(rewind.summary.artists.keys, contains('AC/DC'));
      expect(rewind.summary.artists.keys, isNot(contains('AC')));
    },
  );

  test('same-day cover survives missing and temporary replacement', () async {
    const track = ListeningTrack(
      key: 'a',
      title: 'A',
      artist: 'Artist',
      album: 'Album',
      artwork: '/data/files/covers/a.jpg',
    );
    await writeListeningDeltas(db, [
      ListeningDelta('2026-01-01', track, 60000, 1),
    ]);
    const missing = ListeningTrack(
      key: 'a',
      title: 'A',
      artist: 'Artist',
      album: 'Album',
    );
    await writeListeningDeltas(db, [
      ListeningDelta('2026-01-01', missing, 1000, 0),
    ]);
    expect((await db.query('listening')).single['artwork'], track.artwork);
    expect(
      durableCoverReference('${Directory.systemTemp.path}/transient.jpg'),
      isNull,
    );
    expect(durableCoverReference('http://127.0.0.1:9999/cover'), isNull);
    expect(durableCoverReference(track.artwork), track.artwork);
  });
}
