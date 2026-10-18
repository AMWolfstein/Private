import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/providers/local_artist_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/services/listening_statistics.dart';
import 'support/sqlite_process_database.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(localLibraryEnabled: true);
}

class _Library extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() => LocalLibraryState();
}

LocalLibraryItem item(int i) => LocalLibraryItem(
  id: '$i',
  trackName: 'Song $i',
  artistName: 'Artist',
  albumName: 'Album',
  filePath: '/music/$i.opus',
  scannedAt: DateTime(2026),
);

void main() {
  for (final history in [false, true]) {
    test(
      'popular scans all bounded pages and caps at 20 (history=$history)',
      () async {
        final offsets = <int>[];
        var statsReads = 0;
        final container = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(_Settings.new),
            localLibraryProvider.overrideWith(_Library.new),
            localArtistPopularRandomProvider.overrideWithValue(Random(17)),
            localArtistTrackLoaderProvider.overrideWithValue((request) async {
              offsets.add(request.offset);
              expect(request.artist, 'Artist');
              return QueueLibraryDbPage(
                rows: [
                  for (
                    var i = request.offset;
                    i < min(request.offset + 40, 81);
                    i++
                  )
                    {'source': 'local', 'item': item(i).toJson()},
                ],
                nextCursor: QueueLibraryDbCursor([request.offset + 40]),
              );
            }),
            localArtistPlayCountsLoaderProvider.overrideWithValue((keys) async {
              statsReads++;
              expect(keys.length, lessThanOrEqualTo(80));
              return history
                  ? {for (var i = 0; i < 81; i++) '/music/$i.opus': i}
                  : {};
            }),
          ],
        );
        addTearDown(container.dispose);
        final provider = localArtistPopularProvider('Artist');
        container.listen(provider, (_, _) {});
        final result = await container.read(provider.future);
        expect(result.items.length, 20);
        expect(result.items.map((t) => t.id).toSet().length, 20);
        expect(offsets, [0, 40, 80]);
        expect(statsReads, 3);
        if (history) {
          expect(
            result.items.map((t) => t.id),
            List.generate(20, (i) => '${80 - i}'),
          );
        } else {
          final random = Random(17);
          final expected = [
            for (var i = 0; i < 81; i++) (id: '$i', tie: random.nextDouble()),
          ]..sort((a, b) => b.tie.compareTo(a.tie));
          expect(
            result.items.map((t) => t.id),
            expected.take(20).map((t) => t.id),
          );
          expect(result.items.any((t) => int.parse(t.id) >= 40), true);
          expect(
            container.read(provider).requireValue.items,
            same(result.items),
          );
        }
      },
    );
  }
  test('fewer than 20 songs are returned once each', () async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        localLibraryProvider.overrideWith(_Library.new),
        localArtistTrackLoaderProvider.overrideWithValue(
          (request) async => QueueLibraryDbPage(
            rows: [
              for (var i = 0; i < 3; i++)
                {'source': 'local', 'item': item(i).toJson()},
            ],
            nextCursor: null,
          ),
        ),
        localArtistPlayCountsLoaderProvider.overrideWithValue(
          (keys) async => {},
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(localArtistPopularProvider('Artist'), (_, _) {});
    final result = await container.read(
      localArtistPopularProvider('Artist').future,
    );
    expect(result.items.map((t) => t.id).toSet(), {'0', '1', '2'});
    expect(result.hasMore, false);
  });
  test(
    'SQLite popularity sums plays across days and excludes other track keys',
    () async {
      final db = await SqliteProcessDatabase.open();
      addTearDown(db.close);
      await db.execute(
        'CREATE TABLE listening(day TEXT, track_key TEXT, plays INTEGER, milliseconds INTEGER)',
      );
      await db.execute(
        "INSERT INTO listening VALUES ('2026-01-01','/music/1.opus',2,90000), ('2026-01-02','/music/1.opus',3,100000), ('2026-01-01','/music/2.opus',1,999999), ('2026-01-01','other',90,999999)",
      );
      expect(
        await readListeningPlayCounts(db, [
          '/music/1.opus',
          '/music/2.opus',
          'missing',
        ]),
        {'/music/1.opus': 5, '/music/2.opus': 1},
      );
      expect(await readListeningPlayCounts(db, []), isEmpty);
    },
  );
}
