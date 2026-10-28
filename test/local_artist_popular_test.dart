import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/providers/local_artist_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/services/library/library_database.dart';
import 'package:sistrum/services/listening_statistics.dart';
import 'support/sqlite_process_database.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

class _Library extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() => LocalLibraryState();

  void refreshIndex() {
    state = state.copyWith(loadedIndexVersion: state.loadedIndexVersion + 1);
  }
}

class _CountingRandom implements Random {
  final _random = Random(17);
  int draws = 0;

  @override
  double nextDouble() {
    draws++;
    return _random.nextDouble();
  }

  @override
  bool nextBool() => _random.nextBool();

  @override
  int nextInt(int max) => _random.nextInt(max);
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
  test(
    'flushing listening stats happens once per selection (PERF-601)',
    () async {
      var flushes = 0;
      final events = <String>[];
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          localLibraryProvider.overrideWith(_Library.new),
          listeningFlushProvider.overrideWithValue(() async {
            flushes++;
            events.add('flush');
          }),
          localArtistTrackLoaderProvider.overrideWithValue((request) async {
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
            events.add('counts');
            return {};
          }),
        ],
      );
      addTearDown(container.dispose);
      final provider = localArtistPopularProvider('Artist');
      container.listen(provider, (_, _) {});
      final result = await container.read(provider.future);
      expect(result.items.length, 20);
      expect(flushes, 1);
      // PERF-601: the single flush must precede every play-count read, not run
      // after the paging loop.
      expect(events.first, 'flush');
      expect(events.indexOf('counts'), greaterThan(0));
    },
  );
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
  for (final history in [false, true]) {
    test(
      'popular priorities survive index refreshes (history=$history)',
      () async {
        var tracks = List.generate(81, item);
        var plays = history ? {'/music/0.opus': 8, '1': 3} : <String, int>{};
        final random = _CountingRandom();
        final container = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(_Settings.new),
            localLibraryProvider.overrideWith(_Library.new),
            localArtistPopularRandomProvider.overrideWithValue(random),
            localArtistTrackLoaderProvider.overrideWithValue((request) async {
              return QueueLibraryDbPage(
                rows: tracks
                    .skip(request.offset)
                    .take(40)
                    .map((track) => {'source': 'local', 'item': track.toJson()})
                    .toList(),
                nextCursor: QueueLibraryDbCursor([request.offset + 40]),
              );
            }),
            localArtistPlayCountsLoaderProvider.overrideWithValue(
              (keys) async => plays,
            ),
          ],
        );
        addTearDown(container.dispose);
        final provider = localArtistPopularProvider('Artist');
        final subscription = container.listen(provider, (_, _) {});
        final initial = (await container.read(provider.future)).items;
        final ids = initial.map((track) => track.id).toList();
        expect(random.draws, 81);
        if (history) expect(ids.take(2), ['0', '1']);

        // A scan changes only the version; an edit may also reorder SQL pages.
        final library =
            container.read(localLibraryProvider.notifier) as _Library;
        library.refreshIndex();
        expect(
          (await container.read(
            provider.future,
          )).items.map((track) => track.id),
          ids,
        );
        tracks = tracks.reversed.toList();
        library.refreshIndex();
        expect(
          (await container.read(
            provider.future,
          )).items.map((track) => track.id),
          ids,
        );

        // Deleting one pick fills the gap without rerolling surviving priorities.
        tracks = tracks.where((track) => track.id != ids.last).toList();
        library.refreshIndex();
        final afterDelete = (await container.read(provider.future)).items;
        expect(afterDelete, hasLength(20));
        expect(afterDelete.map((track) => track.id).take(19), ids.take(19));
        expect(afterDelete.any((track) => track.id == ids.last), isFalse);

        // Newly recorded plays still outrank the stable unplayed selection.
        final promoted = tracks.firstWhere(
          (track) => !afterDelete.any((picked) => picked.id == track.id),
        );
        plays = {...plays, promoted.filePath: 100};
        library.refreshIndex();
        final afterPromotion = (await container.read(provider.future)).items;
        expect(afterPromotion.first.id, promoted.id);
        expect(random.draws, 81);

        // A new track gets one independent draw; existing IDs keep their draws.
        tracks.add(item(81));
        library.refreshIndex();
        expect((await container.read(provider.future)).items, hasLength(20));
        expect(random.draws, 82);

        // Leaving the page releases the priorities; reopening gets fresh draws.
        subscription.close();
        await container.pump();
        container.listen(provider, (_, _) {});
        final reopened = (await container.read(provider.future)).items;
        expect(reopened, hasLength(20));
        expect(reopened.first.id, promoted.id);
        expect(random.draws, 82 + tracks.length);
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
