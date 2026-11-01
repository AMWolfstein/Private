import 'dart:async';
import 'dart:math';
import 'package:sistrum/core/models/playable_media.dart';
import 'package:sistrum/services/library/collections/collection_browser_reader.dart';
import 'package:sistrum/services/playback/browser/media_library_catalog.dart';

class FakeMediaLibraryCatalog implements MediaLibraryCatalog {
  FakeMediaLibraryCatalog({int count = 1103})
    : songs = List.generate(
        count,
        (i) => PlayableMedia(
          id: 'song-$i',
          source: '/music/$i.flac',
          title: 'Song $i',
          artist: 'Artist ${i % 3}',
          album: 'Album ${i % 2}',
          artUri: 'file:///private/library_covers/$i.jpg',
        ),
      );
  final List<PlayableMedia> songs;
  final requests =
      <
        ({
          int offset,
          int limit,
          String? album,
          String? artist,
          String? search,
          String? playlist,
          bool loved,
        })
      >[];
  Completer<BrowserTrackPage>? gate;
  void Function()? onPage;
  @override
  Future<BrowserTrackPage> tracks({
    int offset = 0,
    int limit = 200,
    String? albumKey,
    String? artist,
    String? search,
    String? playlistId,
    bool loved = false,
  }) async {
    requests.add((
      offset: offset,
      limit: limit,
      album: albumKey,
      artist: artist,
      search: search,
      playlist: playlistId,
      loved: loved,
    ));
    final pending = gate;
    if (pending != null) {
      gate = null;
      return pending.future;
    }
    var values = songs;
    if (albumKey != null) {
      values = values
          .where((s) => s.album == 'Album ${albumKey.split('-').last}')
          .toList();
    }
    if (artist != null) {
      values = values.where((s) => s.artist == artist).toList();
    }
    if (search != null) {
      values = values
          .where((s) => s.title.toLowerCase().contains(search.toLowerCase()))
          .toList();
    }
    if (loved) values = values.take(3).toList();
    if (playlistId != null) values = values.reversed.take(7).toList();
    final start = min(offset, values.length),
        end = min(offset + limit, values.length);
    onPage?.call();
    return (items: values.sublist(start, end), hasMore: end < values.length);
  }

  @override
  Future<PlayableMedia?> track(String id) async =>
      songs.where((s) => s.id == id).firstOrNull;
  @override
  Future<List<BrowserRelease>> albums({
    int offset = 0,
    int limit = 200,
    String? artist,
    String? search,
  }) async =>
      [
            for (var i = 0; i < 2; i++)
              (
                key: 'album-$i',
                name: 'Album $i',
                artist: 'Artist 0',
                cover: '/private/library_covers/album $i.jpg',
              ),
          ]
          .where(
            (a) =>
                search == null ||
                a.name.toLowerCase().contains(search.toLowerCase()),
          )
          .skip(offset)
          .take(limit)
          .toList();
  @override
  Future<List<BrowserArtist>> artists({
    int offset = 0,
    int limit = 200,
    String? search,
  }) async =>
      [
            for (var i = 0; i < 3; i++)
              (
                name: 'Artist $i',
                cover: '/private/library_covers/artist$i.jpg',
              ),
          ]
          .where(
            (a) =>
                search == null ||
                a.name.toLowerCase().contains(search.toLowerCase()),
          )
          .skip(offset)
          .take(limit)
          .toList();
  @override
  Future<List<BrowserPlaylist>> playlists({
    int offset = 0,
    int limit = 200,
    String? search,
  }) async =>
      <BrowserPlaylist>[
            (
              id: 'p1',
              name: 'Road trip',
              cover: '/private/playlist_covers/road.jpg',
              count: 7,
            ),
          ]
          .where(
            (p) =>
                search == null ||
                p.name.toLowerCase().contains(search.toLowerCase()),
          )
          .skip(offset)
          .take(limit)
          .toList();
}
