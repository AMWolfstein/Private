part of 'app_library_screen.dart';

extension _AppLibraryScreenStatePart1 on _AppLibraryScreenState {
  bool get _overview => widget.page == AppLibraryPage.overview;

  /// Both artist lists show one name per row; they differ in the credits read.
  bool get _artists =>
      widget.page == AppLibraryPage.artists ||
      widget.page == AppLibraryPage.albumArtists;
  bool get _albumArtists => widget.page == AppLibraryPage.albumArtists;
  LibraryBrowseRequest get _request => (
    artists: _artists,
    albumArtists: _albumArtists,
    artist: widget.artist,
    credit: null,
    search: '',
    sort: _sort,
    limit: 40,
    releaseKind: null,
  );
  Future<void> _refresh() async {
    if (_overview) return;
    final provider = libraryBrowseProvider(_request);
    ref.invalidate(provider);
    try {
      await ref.read(provider.future);
    } catch (_) {
      // The error row offers its own Retry; pull-to-refresh must not rethrow.
    }
  }

  void _retry() {
    final provider = libraryBrowseProvider(_request);
    if (ref.read(provider).value?.loadMoreError != null) {
      // Keep the pages already loaded instead of starting the section over.
      unawaited(ref.read(provider.notifier).loadMore());
      return;
    }
    ref.invalidate(provider);
  }

  void _openPage(AppLibraryPage page, {String? artist}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => artist != null
            ? LocalArtistScreen(artistName: artist)
            : Scaffold(
                body: AppLibraryScreen(
                  page: page,
                  artist: artist,
                  onOpenSection: widget.onOpenSection,
                ),
              ),
      ),
    );
  }

  Future<void> _openAlbum(LibraryBrowseEntry entry) async {
    Future<List<LocalLibraryItem>> loadTracks() async {
      final rows = await ref
          .read(libraryDatabaseProvider)
          .getBrowseLocalAlbumRowsByKey(entry.key);
      return rows.map(LocalLibraryItem.fromJson).toList(growable: false);
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalAlbumScreen(
          albumName: entry.name,
          artistName: entry.artist,
          coverPath: entry.cover,
          loadTracks: loadTracks,
        ),
      ),
    );
  }

  Future<void> _jumpToLetter(LibraryAlphabetEntry entry) async {
    final generation = ++_alphabetGeneration;
    _alphabetScroll.cancel();
    final request = _request;
    final version = ref.read(localLibraryProvider).loadedIndexVersion;
    final provider = libraryBrowseProvider(request);
    bool current() =>
        mounted &&
        generation == _alphabetGeneration &&
        _request == request &&
        ref.read(localLibraryProvider).loadedIndexVersion == version;
    while (current()) {
      final state = ref.read(provider).asData?.value;
      if (state == null) return;
      if (state.entries.length > entry.offset) break;
      if (state.loadMoreError != null || !state.hasMore) return;
      if (state.isLoadingMore) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
      } else {
        await ref.read(provider.notifier).loadMore();
      }
    }
    if (!current()) return;
    await WidgetsBinding.instance.endOfFrame;
    if (current()) await _alphabetScroll.reveal(entry.offset);
  }
}
