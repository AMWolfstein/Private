import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:sistrum/services/library/collections/collection_browser_reader.dart';
import 'package:sistrum/core/models/playable_media.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/services/playback/browser/browser_cover_provider.dart';
import 'package:sistrum/services/playback/browser/media_library_catalog.dart';

typedef BrowserQueue = ({List<PlayableMedia> items, int index, bool shuffle});

/// Local-only media browser. Public IDs describe library identities and their
/// parent collection; an external caller cannot use one to supply a file path.
class MediaLibraryBrowser {
  MediaLibraryBrowser({
    required this.catalog,
    required this.strings,
    Future<BrowserCoverProvider?> Function() coverProvider =
        BrowserCoverProvider.load,
  }) : _loadCovers = coverProvider;
  final MediaLibraryCatalog catalog;
  final AppLocalizations Function() strings;
  final Future<BrowserCoverProvider?> Function() _loadCovers;
  BrowserCoverProvider? _covers;
  Future<void>? _loadingCovers;
  static const scheme = 'sistrum-browse';
  static const songsId = '$scheme:songs',
      albumsId = '$scheme:albums',
      artistsId = '$scheme:artists',
      playlistsId = '$scheme:playlists',
      lovedId = '$scheme:loved',
      shuffleId = '$scheme:shuffle';
  static const listLimit = 200;
  static const rootExtras = <String, dynamic>{
    'android.media.browse.SEARCH_SUPPORTED': true,
    AndroidContentStyle.supportedKey: true,
    AndroidContentStyle.browsableHintKey: AndroidContentStyle.listItemHintValue,
    AndroidContentStyle.playableHintKey: AndroidContentStyle.listItemHintValue,
  };
  static const _grid = <String, dynamic>{
    AndroidContentStyle.browsableHintKey: AndroidContentStyle.gridItemHintValue,
  };
  static const _groupKey =
      'android.media.browse.CONTENT_STYLE_GROUP_TITLE_HINT';

  /// Android uses an audio focus with EXTRA_MEDIA_TITLE for a named song.
  /// Without a named focus or query the handler resumes its current session.
  static String searchText(String query, Map<String, dynamic>? extras) {
    final kind = (extras?['android.intent.extra.focus']?.toString() ?? '')
        .split('/')
        .last;
    final field = const {'audio', 'music', 'song'}.contains(kind)
        ? 'title'
        : kind;
    final value = extras?['android.intent.extra.$field'];
    return value is String && value.trim().isNotEmpty
        ? value.trim()
        : query.trim();
  }

  static bool isBrowserId(String id) => id.startsWith('$scheme:');
  static String _id(String path, Map<String, String> query) =>
      Uri(scheme: scheme, path: path, queryParameters: query).toString();
  static Uri? _parse(String id) {
    try {
      final uri = Uri.parse(id);
      uri.queryParameters; // Validate percent encoding before dispatch.
      return uri.scheme == scheme && !uri.hasAuthority && !uri.hasFragment
          ? uri
          : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> _prepareCovers() async {
    if (_covers != null) return;
    final pending = _loadingCovers ??= () async {
      try {
        _covers = await _loadCovers();
      } catch (_) {
        _covers = null;
      }
    }();
    try {
      await pending;
    } finally {
      if (identical(_loadingCovers, pending)) _loadingCovers = null;
    }
  }

  Uri? _art(String? value) => _covers?.uriFor(value);
  MediaItem _song(
    PlayableMedia media,
    String parent, {
    String? group,
    int? position,
  }) => MediaItem(
    id: _id('track', {
      'parent': parent,
      'id': media.id,
      if (position != null) 'position': '$position',
    }),
    title: media.title.isEmpty ? strings().unknownTitle : media.title,
    artist: media.artist,
    album: media.album,
    duration: media.duration,
    artUri: _art(media.artUri),
    extras: {_groupKey: ?group, if (media.explicit) 'explicit': true},
  );
  MediaItem _album(BrowserRelease album, {String? group}) => MediaItem(
    id: _id('album', {
      'key': album.key,
      'name': album.name,
      'artist': album.artist,
    }),
    title: album.name.isEmpty ? strings().unknownTitle : album.name,
    artist: album.artist,
    artUri: _art(album.cover),
    playable: false,
    extras: {_groupKey: ?group},
  );
  MediaItem _artist(BrowserArtist artist, {String? group}) => MediaItem(
    id: _id('artist', {'name': artist.name}),
    title: artist.name,
    artUri: _art(artist.cover),
    playable: false,
    extras: {..._grid, _groupKey: ?group},
  );

  /// Page bounds apply at the database boundary, including the leading
  /// Shuffle/Loved rows, so later pages neither repeat nor omit a song.
  static ({int offset, int size})? _page(Map<String, dynamic>? options) {
    final page = options?['android.media.browse.extra.PAGE'];
    final size = options?['android.media.browse.extra.PAGE_SIZE'];
    if (page == -1 && size == -1) return (offset: 0, size: listLimit);
    if (page == null && size == null) return (offset: 0, size: listLimit);
    if (page is! int ||
        size is! int ||
        page < 0 ||
        size <= 0 ||
        size > 500 ||
        page > 1000000) {
      return null;
    }
    return (offset: page * size, size: size);
  }

  Future<List<MediaItem>> children(
    String parent, [
    Map<String, dynamic>? options,
  ]) async {
    final page = _page(options);
    if (page == null) return const [];
    final l10n = strings();
    if (parent == AudioService.browsableRootId) {
      final tabs = [
        MediaItem(id: songsId, title: l10n.searchSongs, playable: false),
        MediaItem(
          id: albumsId,
          title: l10n.searchAlbums,
          playable: false,
          extras: _grid,
        ),
        MediaItem(id: artistsId, title: l10n.searchArtists, playable: false),
        MediaItem(
          id: playlistsId,
          title: l10n.searchPlaylists,
          playable: false,
        ),
      ];
      return tabs.skip(page.offset).take(page.size).toList();
    }
    final uri = _parse(parent);
    if (uri == null) return const [];
    await _prepareCovers();
    switch (uri.path) {
      case 'songs':
        final leading = page.offset == 0;
        final size = page.size - (leading ? 1 : 0);
        final songs = size == 0
            ? <PlayableMedia>[]
            : (await catalog.tracks(
                offset: max(0, page.offset - 1),
                limit: size,
              )).items;
        return [
          if (leading)
            MediaItem(id: shuffleId, title: l10n.nowPlayingShuffleLibrary),
          for (final (i, song) in songs.indexed)
            if (browserPlayable(song))
              _song(song, parent, position: max(0, page.offset - 1) + i),
        ];
      case 'albums':
      case 'artist':
        if (uri.path == 'artist' &&
            (uri.queryParameters['name'] ?? '').trim().isEmpty) {
          return const [];
        }
        final albums = await catalog.albums(
          offset: page.offset,
          limit: page.size,
          artist: uri.path == 'artist' ? uri.queryParameters['name'] : null,
        );
        return albums.map(_album).toList();
      case 'artists':
        return (await catalog.artists(
          offset: page.offset,
          limit: page.size,
        )).map(_artist).toList();
      case 'playlists':
        final leading = page.offset == 0;
        final size = page.size - (leading ? 1 : 0);
        final lists = size == 0
            ? <BrowserPlaylist>[]
            : await catalog.playlists(
                offset: max(0, page.offset - 1),
                limit: size,
              );
        return [
          if (leading)
            MediaItem(
              id: lovedId,
              title: l10n.collectionLoved,
              playable: false,
            ),
          for (final list in lists)
            MediaItem(
              id: _id('playlist', {'id': list.id}),
              title: list.name,
              artUri: _art(list.cover),
              playable: false,
            ),
        ];
      case 'album':
      case 'loved':
      case 'playlist':
      case 'search':
        final songs = await _tracks(uri, offset: page.offset, limit: page.size);
        return [
          for (final (i, song) in songs.items.indexed)
            if (browserPlayable(song))
              _song(song, parent, position: page.offset + i),
        ];
      default:
        return const [];
    }
  }

  Future<BrowserTrackPage> _tracks(
    Uri parent, {
    int offset = 0,
    int limit = 500,
  }) {
    final query = parent.queryParameters;
    const empty = (items: <PlayableMedia>[], hasMore: false);
    return switch (parent.path) {
      'songs' => catalog.tracks(offset: offset, limit: limit),
      'album' when (query['key'] ?? '').isNotEmpty => catalog.tracks(
        offset: offset,
        limit: limit,
        albumKey: query['key'],
      ),
      'artist' when (query['name'] ?? '').isNotEmpty => catalog.tracks(
        offset: offset,
        limit: limit,
        artist: query['name'],
      ),
      'playlist' when (query['id'] ?? '').isNotEmpty => catalog.tracks(
        offset: offset,
        limit: limit,
        playlistId: query['id'],
      ),
      'loved' => catalog.tracks(offset: offset, limit: limit, loved: true),
      'search' when (query['q'] ?? '').trim().isNotEmpty => catalog.tracks(
        offset: offset,
        limit: limit,
        search: query['q'],
      ),
      _ => Future.value(empty),
    };
  }

  Future<List<PlayableMedia>> _all(
    Uri parent, {
    bool Function()? current,
  }) async {
    final songs = <PlayableMedia>[];
    for (var offset = 0; ; offset += 500) {
      if (current != null && !current()) return const [];
      final page = await _tracks(parent, offset: offset);
      songs.addAll(page.items.where(browserPlayable));
      if (!page.hasMore) return songs;
    }
  }

  Future<MediaItem> present(MediaItem item) async {
    await _prepareCovers();
    return item.copyWith(artUri: _art(item.artUri?.toString()));
  }

  Future<MediaItem?> item(String id) async {
    final uri = _parse(id);
    if (uri?.path != 'track') return null;
    final song = await catalog.track(uri!.queryParameters['id'] ?? '');
    if (song == null) return null;
    await _prepareCovers();
    return _song(
      song,
      uri.queryParameters['parent'] ?? songsId,
      position: int.tryParse(uri.queryParameters['position'] ?? ''),
    );
  }

  Future<BrowserQueue?> queueFor(String id, {bool Function()? current}) async {
    final uri = _parse(id);
    if (uri == null) return null;
    if (uri.path == 'shuffle') {
      final songs = await _all(Uri.parse(songsId), current: current);
      return songs.isEmpty
          ? null
          : (
              items: songs,
              index: Random().nextInt(songs.length),
              shuffle: true,
            );
    }
    if (uri.path != 'track') return null;
    final parent = _parse(uri.queryParameters['parent'] ?? '');
    if (parent == null) return null;
    final songs = await _all(parent, current: current);
    final requested = int.tryParse(uri.queryParameters['position'] ?? '');
    final index =
        requested != null &&
            requested >= 0 &&
            requested < songs.length &&
            songs[requested].id == uri.queryParameters['id']
        ? requested
        : songs.indexWhere((song) => song.id == uri.queryParameters['id']);
    return index < 0 ? null : (items: songs, index: index, shuffle: false);
  }

  Future<List<MediaItem>> search(String query) async {
    final text = query.trim();
    if (text.isEmpty || text.length > 1024) return const [];
    await _prepareCovers();
    final l10n = strings();
    final songs = await catalog.tracks(search: text, limit: 40);
    final albums = await catalog.albums(search: text, limit: 20);
    final artists = await catalog.artists(search: text, limit: 20);
    final lists = await catalog.playlists(search: text, limit: 20);
    return [
      for (final song in songs.items.where(browserPlayable))
        _song(song, _id('search', {'q': text}), group: l10n.searchSongs),
      for (final album in albums) _album(album, group: l10n.searchAlbums),
      for (final artist in artists) _artist(artist, group: l10n.searchArtists),
      for (final list in lists)
        MediaItem(
          id: _id('playlist', {'id': list.id}),
          title: list.name,
          artUri: _art(list.cover),
          playable: false,
          extras: {_groupKey: l10n.searchPlaylists},
        ),
    ];
  }

  Future<BrowserQueue?> queueForSearch(
    String query, [
    Map<String, dynamic>? extras,
    bool Function()? current,
  ]) async {
    final focus = extras?['android.intent.extra.focus']?.toString() ?? '';
    final kind = focus.split('/').last;
    final text = searchText(query, extras);
    if (text.length > 1024) return null;
    if (text.isEmpty) return queueFor(shuffleId, current: current);
    Future<List<PlayableMedia>> albums() async {
      final hits = await catalog.albums(search: text, limit: 1);
      return hits.isEmpty
          ? const []
          : _all(
              Uri.parse(_id('album', {'key': hits.first.key})),
              current: current,
            );
    }

    Future<List<PlayableMedia>> artists() async {
      final hits = await catalog.artists(search: text, limit: 1);
      return hits.isEmpty
          ? const []
          : _all(
              Uri.parse(_id('artist', {'name': hits.first.name})),
              current: current,
            );
    }

    Future<List<PlayableMedia>> playlists() async {
      final hits = await catalog.playlists(search: text, limit: 1);
      return hits.isEmpty
          ? const []
          : _all(
              Uri.parse(_id('playlist', {'id': hits.first.id})),
              current: current,
            );
    }

    Future<List<PlayableMedia>> songs() =>
        _all(Uri.parse(_id('search', {'q': text})), current: current);
    final first = switch (kind) {
      'album' => albums,
      'artist' => artists,
      'playlist' => playlists,
      _ => songs,
    };
    final order = {first, songs, albums, artists, playlists};
    for (final find in order) {
      if (current != null && !current()) return null;
      final matches = await find();
      if (matches.isNotEmpty) return (items: matches, index: 0, shuffle: false);
    }
    return null;
  }
}
