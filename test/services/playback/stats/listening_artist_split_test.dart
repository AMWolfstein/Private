import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/library/browse/library_tag_credits.dart';
import 'package:sistrum/services/playback/stats/listening_statistics.dart';

import '../../../support/sqlite_process_database.dart';

void main() {
  group('artist totals follow the artist separators', () {
    late SqliteProcessDatabase db;

    setUp(() async {
      db = await SqliteProcessDatabase.open();
      await db.execute('''
        CREATE TABLE listening (
          day TEXT, track_key TEXT, title TEXT, artist TEXT, album TEXT,
          artwork TEXT, milliseconds INTEGER, plays INTEGER,
          PRIMARY KEY(day, track_key)
        )
      ''');
      await db.rawInsert(
        'INSERT INTO listening '
        '(day, track_key, title, artist, album, artwork, milliseconds, plays) '
        "VALUES ('2026-10-01', 'song', 'Song', 'Amr Mostafa, Hamo El Morshedy', "
        "'Album', NULL, 600000, 2)",
      );
    });
    tearDown(() async => db.close());

    test(
      'a track with several artists adds its time to each of them',
      () async {
        final summary = await readListeningSummary(
          db,
          DateTime(2026, 10),
          DateTime(2026, 11),
        );
        expect(summary.artists, {
          'Amr Mostafa': 600000,
          'Hamo El Morshedy': 600000,
        });
      },
    );

    test('the split follows the rules it is given', () async {
      final summary = await readListeningSummary(
        db,
        DateTime(2026, 10),
        DateTime(2026, 11),
        rules: const TagCreditRules(artistDelimiters: [';']),
      );
      expect(summary.artists, {'Amr Mostafa, Hamo El Morshedy': 600000});
    });
  });
}
