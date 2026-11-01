import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/services/playback/browser/browser_cover_provider.dart';
import 'package:sistrum/services/playback/browser/media_library_browser.dart';
import '../../../support/media_library_catalog_harness.dart';

const covers = BrowserCoverProvider(
  authority: 'local.app.covers',
  folders: {
    'library_covers': '/private/library_covers',
    'playlist_covers': '/private/playlist_covers',
  },
);
Map<String, dynamic> page(int number, int size) => {
  'android.media.browse.extra.PAGE': number,
  'android.media.browse.extra.PAGE_SIZE': size,
};
void main() {
  MediaLibraryBrowser browser(
    FakeMediaLibraryCatalog data, {
    Future<BrowserCoverProvider?> Function()? load,
  }) => MediaLibraryBrowser(
    catalog: data,
    strings: () => lookupAppLocalizations(const Locale('en')),
    coverProvider: load ?? () async => covers,
  );
  test(
    'repeated playlist songs retain distinct ids and the chosen occurrence',
    () async {
      final data = FakeMediaLibraryCatalog(count: 5);
      data.songs.insert(3, data.songs[1]);
      final app = browser(data);
      final lists = await app.children(MediaLibraryBrowser.playlistsId);
      final tracks = await app.children(lists[1].id);
      expect(tracks[2].title, tracks[4].title);
      expect(tracks[2].id, isNot(tracks[4].id));
      final selection = await app.queueFor(tracks[4].id);
      expect(selection!.index, 4);
      expect(selection.items.length, 6);
    },
  );
  test(
    'structured audio focus reads the named title without a query string',
    () async {
      final app = browser(FakeMediaLibraryCatalog(count: 20));
      final result = await app.queueForSearch('', {
        'android.intent.extra.focus': 'vnd.android.cursor.item/audio',
        'android.intent.extra.title': 'Song 12',
      });
      expect(result!.items.single.title, 'Song 12');
      expect(
        MediaLibraryBrowser.searchText('', {
          'android.intent.extra.focus': 'vnd.android.cursor.item/audio',
        }),
        '',
      );
    },
  );
  test(
    'root shows the four library tabs before loading art or any song page',
    () async {
      final data = FakeMediaLibraryCatalog();
      var loads = 0;
      final app = browser(
        data,
        load: () async {
          loads++;
          return covers;
        },
      );
      final roots = await app.children(AudioService.browsableRootId);
      expect(roots.map((m) => m.title), [
        'Songs',
        'Albums',
        'Artists',
        'Playlists',
      ]);
      expect(roots.every((m) => m.playable == false), true);
      expect(data.requests, isEmpty);
      expect(loads, 0);
      expect(
        MediaLibraryBrowser.rootExtras['android.media.browse.SEARCH_SUPPORTED'],
        true,
      );
      expect(
        (await app.children(
          AudioService.browsableRootId,
          page(1, 2),
        )).map((m) => m.id),
        [MediaLibraryBrowser.artistsId, MediaLibraryBrowser.playlistsId],
      );
    },
  );
  test(
    'song paging accounts for Shuffle without repeating or dropping rows',
    () async {
      final data = FakeMediaLibraryCatalog(count: 12), app = browser(data);
      final all = <MediaItem>[];
      for (var p = 0; p < 5; p++) {
        all.addAll(await app.children(MediaLibraryBrowser.songsId, page(p, 3)));
      }
      expect(all.first.id, MediaLibraryBrowser.shuffleId);
      expect(
        all.skip(1).map((s) => s.title),
        List.generate(12, (i) => 'Song $i'),
      );
      expect(all.map((s) => s.id).toSet().length, 13);
      expect(data.requests.every((r) => r.limit <= 3), true);
      expect(
        await app.children(MediaLibraryBrowser.songsId, page(-1, -1)),
        isNotEmpty,
      );
      for (final options in [
        page(-2, 3),
        page(0, 0),
        page(0, 501),
        {'android.media.browse.extra.PAGE': 'bad'},
      ]) {
        expect(
          await app.children(MediaLibraryBrowser.songsId, options),
          isEmpty,
        );
      }
    },
  );
  test(
    'selecting a later page builds the whole collection beyond 500 rows',
    () async {
      final data = FakeMediaLibraryCatalog(), app = browser(data);
      final entries = await app.children(
        MediaLibraryBrowser.songsId,
        page(70, 10),
      );
      final selection = entries[4];
      final queue = await app.queueFor(selection.id);
      expect(queue!.items.length, 1103);
      expect(queue.items[queue.index].title, selection.title);
      expect(queue.shuffle, false);
      expect(data.requests.every((r) => r.limit <= 500), true);
      final shuffle = await app.queueFor(MediaLibraryBrowser.shuffleId);
      expect(shuffle!.shuffle, true);
      expect(shuffle.items.length, 1103);
      expect((await app.item(selection.id))!.id, selection.id);
    },
  );
  test(
    'albums artists loved and playlists retain parent queue context',
    () async {
      final app = browser(FakeMediaLibraryCatalog(count: 18));
      final albums = await app.children(MediaLibraryBrowser.albumsId);
      expect(albums.every((a) => a.playable == false), true);
      final albumTracks = await app.children(albums.first.id);
      final albumQueue = await app.queueFor(albumTracks.last.id);
      expect(albumQueue!.items.every((s) => s.album == 'Album 0'), true);
      expect(albumQueue.index, albumQueue.items.length - 1);
      final artists = await app.children(MediaLibraryBrowser.artistsId);
      expect(await app.children(artists.first.id), isNotEmpty);
      final lists = await app.children(MediaLibraryBrowser.playlistsId);
      expect(lists.first.id, MediaLibraryBrowser.lovedId);
      final loved = await app.children(lists.first.id);
      expect(loved.length, 3);
      final entries = await app.children(lists[1].id);
      final queue = await app.queueFor(entries[2].id);
      expect(queue!.items.length, 7);
      expect(queue.items[queue.index].title, entries[2].title);
      expect(
        (await app.children(
          MediaLibraryBrowser.playlistsId,
          page(1, 1),
        )).single.id,
        lists[1].id,
      );
    },
  );
  test(
    'search is grouped and structured voice focus chooses the named kind',
    () async {
      final app = browser(FakeMediaLibraryCatalog(count: 30));
      final songs = await app.search('Song 2');
      expect(songs, isNotEmpty);
      expect(
        songs.every(
          (s) => s.extras!.containsKey(
            'android.media.browse.CONTENT_STYLE_GROUP_TITLE_HINT',
          ),
        ),
        true,
      );
      expect((await app.search('Album 0')).single.playable, false);
      final artist = await app.queueForSearch('wrong query', {
        'android.intent.extra.focus': 'vnd.android.cursor.item/artist',
        'android.intent.extra.artist': 'Artist 1',
      });
      expect(artist!.items.every((s) => s.artist == 'Artist 1'), true);
      final album = await app.queueForSearch('Album 1', {
        'android.intent.extra.focus': 'vnd.android.cursor.item/album',
      });
      expect(album!.items.every((s) => s.album == 'Album 1'), true);
      expect((await app.queueForSearch('Road trip'))!.items.length, 7);
      expect(await app.search('   '), isEmpty);
      expect(await app.search('x' * 1025), isEmpty);
    },
  );
  test(
    'art provider discovery retries failures and coalesces concurrent requests',
    () async {
      var attempts = 0;
      final gate = Completer<BrowserCoverProvider?>();
      final data = FakeMediaLibraryCatalog(count: 3);
      final app = browser(
        data,
        load: () async {
          attempts++;
          return attempts == 1 ? null : gate.future;
        },
      );
      final missing = await app.children(MediaLibraryBrowser.songsId);
      expect(missing.last.artUri, isNull);
      final albums = app.children(MediaLibraryBrowser.albumsId);
      final artists = app.children(MediaLibraryBrowser.artistsId);
      await Future<void>.delayed(Duration.zero);
      expect(attempts, 2);
      gate.complete(covers);
      expect((await albums).first.artUri!.scheme, 'content');
      await artists;
      final songs = await app.children(MediaLibraryBrowser.songsId);
      expect(songs.last.artUri!.host, 'local.app.covers');
      expect(attempts, 2);
    },
  );
  test(
    'unsupported ids and canceled pagination cannot supply an arbitrary path',
    () async {
      final data = FakeMediaLibraryCatalog(), app = browser(data);
      for (final id in [
        'file:///secret.flac',
        'https://example.com/song',
        'sistrum-browse:track?id=%',
        'sistrum-browse:track?parent=https%3A%2F%2Fexample.com&id=x',
        'sistrum-browse:album',
      ]) {
        expect(await app.queueFor(id), isNull);
        expect(await app.children(id), isEmpty);
      }
      var current = true;
      data.onPage = () {
        current = false;
      };
      expect(
        await app.queueFor(
          MediaLibraryBrowser.shuffleId,
          current: () => current,
        ),
        isNull,
      );
      expect(data.requests.length, 1);
    },
  );
  test(
    'cover mapping rejects network loopback arbitrary content and nested paths',
    () {
      expect(
        covers.uriFor('/private/library_covers/art space.jpg')!.toString(),
        'content://local.app.covers/library_covers/art%20space.jpg',
      );
      expect(
        covers.uriFor('file:///private/library_covers/art%20space.jpg'),
        covers.uriFor('/private/library_covers/art space.jpg'),
      );
      for (final path in [
        'http://127.0.0.1:123/a',
        'https://example.com/a',
        'network://a',
        'content://other/cover',
        '/secret/file.jpg',
        '/private/library_covers/sub/a.jpg',
        '/private/library_covers/.private',
      ]) {
        expect(covers.uriFor(path), isNull);
      }
    },
  );
}
