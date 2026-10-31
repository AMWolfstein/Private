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
    completeness: _completeness,
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

  Future<void> _chooseSort() async {
    final selected = await showAppBottomSheet<String>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in [
            ('a-z', context.l10n.searchSortTitleAZ),
            ('latest', context.l10n.libraryRecentlyAdded),
            if (!_artists) ...[
              ('size-desc', context.l10n.libraryFilterSortSizeLargest),
              ('size-asc', context.l10n.libraryFilterSortSizeSmallest),
            ],
          ])
            ListTile(
              title: Text(option.$2),
              trailing: _sort == option.$1 ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, option.$1),
            ),
        ],
      ),
    );
    if (!mounted || selected == null || selected == _sort) return;
    _rebuild(() {
      _sort = selected;
      _rows = const [];
    });
    _scroll.jumpTo(0);
  }

  Future<void> _chooseCompleteness() async {
    final selected = await showAppBottomSheet<String>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in [
            ('', context.l10n.libraryFilterAll),
            (incompleteAlbumFilter, context.l10n.libraryFilterIncompleteAlbums),
            (
              unknownAlbumCompletenessFilter,
              context.l10n.libraryAlbumCompletenessUnknown,
            ),
          ])
            ListTile(
              title: Text(option.$2),
              trailing: (_completeness ?? '') == option.$1
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(context, option.$1),
            ),
        ],
      ),
    );
    if (!mounted || selected == null || selected == (_completeness ?? '')) {
      return;
    }
    _rebuild(() {
      _completeness = selected.isEmpty ? null : selected;
      _rows = const [];
    });
    _scroll.jumpTo(0);
  }

  Widget _buildCompletenessBadge(AlbumCompleteness completeness) {
    final colors = Theme.of(context).colorScheme;
    final expected = completeness.expected;
    final label = completeness.status == 'unknown'
        ? context.l10n.libraryAlbumCompletenessUnknown
        : expected == null
        ? context.l10n.libraryFilterIncompleteAlbums
        : context.l10n.libraryAlbumMissingTracks(
            completeness.present,
            expected,
            expected - completeness.present,
          );
    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          completeness.badge,
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
