import 'dart:math';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/core/models/playable_media.dart';
import 'package:sistrum/services/library/collections/collection_browser_reader.dart';
import 'package:sistrum/services/library/collections/library_collections_database.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/services/library/local_track_resolver.dart';
import 'package:sistrum/services/library/browse/library_search.dart';
import 'package:sistrum/services/playback/core/playable_media_factory.dart';
import 'package:sistrum/utils/files/file_access.dart';

typedef BrowserTrackPage = ({List<PlayableMedia> items, bool hasMore});
typedef BrowserRelease = ({
  String key,
  String name,
  String artist,
  String? cover,
});
typedef BrowserArtist = ({String name, String? cover});

abstract interface class MediaLibraryCatalog {
  Future<BrowserTrackPage> tracks({
    int offset = 0,
    int limit = 200,
    String? albumKey,
    String? artist,
    String? search,
    String? playlistId,
    bool loved = false,
  });
  Future<List<BrowserRelease>> albums({
    int offset = 0,
    int limit = 200,
    String? artist,
    String? search,
  });
  Future<List<BrowserArtist>> artists({
    int offset = 0,
    int limit = 200,
    String? search,
  });
  Future<List<BrowserPlaylist>> playlists({
    int offset = 0,
    int limit = 200,
    String? search,
  });
  Future<PlayableMedia?> track(String id);
}

bool browserPlayable(PlayableMedia media) =>
    (media.source.startsWith('/') || media.source.startsWith('content://')) &&
    !isCueVirtualPath(media.source);

class LocalMediaLibraryCatalog implements MediaLibraryCatalog {
  const LocalMediaLibraryCatalog({
    required this.library,
    required this.collections,
  });
  final LibraryDatabase library;
  final LibraryCollectionsDatabase collections;

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
    if (loved || playlistId != null) {
      final page = await CollectionBrowserReader(
        await collections.database,
      ).tracks(playlistId: playlistId, offset: offset, limit: limit);
      final resolved = await LocalTrackResolver(library).resolve(page.tracks);
      return (
        items: [
          for (final item in resolved)
            if (item != null) playableFromLocal(item),
        ].where(browserPlayable).toList(),
        hasMore: page.hasMore,
      );
    }
    List<Map<String, dynamic>> rows;
    var hasMore = false;
    if (albumKey != null) {
      final album = await library.getBrowseLocalAlbumRowsByKey(albumKey);
      // The shared loader already supplies the phone's disc/track/title order.
      final start = min(offset, album.length);
      rows = album.sublist(start, min(start + limit, album.length));
      hasMore = start + rows.length < album.length;
    } else {
      final page = await library.getBrowseTrackPage(
        LibraryBrowseDbQuery(
          offset: offset,
          limit: limit,
          albumArtist: artist,
          searchQuery: search,
          sortMode: 'a-z',
          includeSingleTrackAlbums: true,
        ),
      );
      rows = page.rows.map(LocalLibraryItem.envelopeItem).toList();
      hasMore = rows.length == limit;
    }
    return (
      items: rows
          .map(LocalLibraryItem.fromJson)
          .map(playableFromLocal)
          .where(browserPlayable)
          .toList(),
      hasMore: hasMore,
    );
  }

  @override
  Future<PlayableMedia?> track(String id) async {
    final row = await library.getById(id);
    if (row == null) return null;
    final media = playableFromLocal(LocalLibraryItem.fromJson(row));
    return browserPlayable(media) ? media : null;
  }

  @override
  Future<List<BrowserRelease>> albums({
    int offset = 0,
    int limit = 200,
    String? artist,
    String? search,
  }) async {
    if (search != null) {
      final hits = await library.searchLibrary(
        query: search,
        kind: LibrarySearchKind.albums,
        offset: offset,
        limit: limit,
      );
      return [
        for (final h in hits)
          (key: h.id, name: h.title, artist: h.artist, cover: h.cover),
      ];
    }
    final page = await library.getBrowseAlbumPage(
      LibraryBrowseDbQuery(
        offset: offset,
        limit: limit,
        albumArtist: artist,
        includeSingleTrackAlbums: true,
        sortMode: 'a-z',
      ),
    );
    return [
      for (final row in page.rows)
        (
          key: row['album_key'] as String? ?? '',
          name: row['album_name'] as String? ?? '',
          artist: row['artist_name'] as String? ?? '',
          cover: row['cover_url'] as String?,
        ),
    ];
  }

  @override
  Future<List<BrowserArtist>> artists({
    int offset = 0,
    int limit = 200,
    String? search,
  }) async {
    if (search != null) {
      final hits = await library.searchLibrary(
        query: search,
        kind: LibrarySearchKind.artists,
        offset: offset,
        limit: limit,
      );
      return [for (final h in hits) (name: h.title, cover: h.cover)];
    }
    final rows = await library.getBrowseArtistRows(
      LibraryBrowseDbQuery(offset: offset, limit: limit, sortMode: 'a-z'),
    );
    return [
      for (final row in rows)
        if ((row['artist_name'] as String? ?? '').isNotEmpty)
          (
            name: row['artist_name'] as String,
            cover: row['cover_url'] as String?,
          ),
    ];
  }

  @override
  Future<List<BrowserPlaylist>> playlists({
    int offset = 0,
    int limit = 200,
    String? search,
  }) async => CollectionBrowserReader(
    await collections.database,
  ).playlists(offset: offset, limit: limit, search: search);
}
