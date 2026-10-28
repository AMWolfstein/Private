import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/local_artist_provider.dart';
import 'package:sistrum/services/library/library_database.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

class _Library extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() => LocalLibraryState();
}

Map<String, dynamic> row(int i) => {
  'source': 'local',
  'item': LocalLibraryItem(
    id: '$i',
    trackName: 'Song $i',
    artistName: 'Artist',
    albumName: 'Album',
    filePath: 'content://music/$i',
    scannedAt: DateTime(2026),
  ).toJson(),
};
QueueLibraryDbPage page(int start, int count) => QueueLibraryDbPage(
  rows: List.generate(count, (i) => row(start + i)),
  nextCursor: QueueLibraryDbCursor([start + count]),
);

void main() {
  test(
    'artist pagination retries failed pages and playback loads the entire local queue',
    () async {
      final requests = <ArtistTrackRequest>[];
      var fail = true;
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          localLibraryProvider.overrideWith(_Library.new),
          localArtistTrackLoaderProvider.overrideWithValue((request) async {
            requests.add(request);
            expect(request.artist, 'Artist');
            if (request.offset == 40 && fail) throw StateError('temporary');
            return page(request.offset, request.offset == 0 ? 40 : 5);
          }),
        ],
      );
      addTearDown(container.dispose);
      final provider = localArtistTracksProvider('Artist');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      expect((await container.read(provider.future)).items.length, 40);
      final notifier = container.read(provider.notifier);
      await notifier.loadMore();
      expect(container.read(provider).requireValue.items.length, 40);
      expect(container.read(provider).requireValue.error, isA<StateError>());
      fail = false;
      await notifier.loadMore();
      expect(container.read(provider).requireValue.items.length, 45);
      expect(container.read(provider).requireValue.hasMore, false);
      expect(requests.last.cursor, const QueueLibraryDbCursor([40]));
      requests.clear();
      expect(
        (await notifier.playbackQueue()).map((t) => t.id),
        List.generate(45, (i) => '$i'),
      );
      expect(requests.map((r) => r.offset), [0, 40]);
    },
  );

  test(
    'closing artist while loading more does not publish a late page',
    () async {
      final pending = Completer<QueueLibraryDbPage>();
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          localLibraryProvider.overrideWith(_Library.new),
          localArtistTrackLoaderProvider.overrideWithValue(
            (request) async =>
                request.offset == 0 ? page(0, 40) : pending.future,
          ),
        ],
      );
      final provider = localArtistTracksProvider('Artist');
      container.listen(provider, (_, _) {});
      await container.read(provider.future);
      final load = container.read(provider.notifier).loadMore();
      container.dispose();
      pending.complete(page(40, 1));
      await load;
    },
  );
}
