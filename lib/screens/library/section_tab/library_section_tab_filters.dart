part of 'library_section_tab.dart';

extension _LibrarySectionTabFilters on _LibrarySectionTabState {
  int get _activeFilterCount {
    int count = 0;
    if (_filterQuality != null) count++;
    if (_filterFormat != null) count++;
    if (_filterMetadata != null) count++;
    return count;
  }

  void _resetFilters() {
    _setState(() {
      _filterQuality = null;
      _filterFormat = null;
      _filterMetadata = null;
      _sortMode = 'latest';
      _resetLibraryPaging();
    });
  }

  void _showFilterSheet(BuildContext context) {
    String? tempQuality = _filterQuality;
    String? tempFormat = _filterFormat;
    String? tempMetadata = _filterMetadata;
    String tempSortMode = _sortMode;

    showAppModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (context) => AppScrollableSheet(
        builder: (context, scrollController) => StatefulBuilder(
          builder: (context, setSheetState) {
            Widget metadataChip(String label, String? mode) => AppChoiceChip(
              label: Text(label),
              selected: tempMetadata == mode,
              onSelected: (_) => setSheetState(() => tempMetadata = mode),
            );

            Widget sortChip(String label, String mode) => AppChoiceChip(
              label: Text(label),
              selected: tempSortMode == mode,
              onSelected: (_) => setSheetState(() => tempSortMode = mode),
            );

            return AppBottomSheet(
              title: context.l10n.libraryFilterTitle,
              titleTrailing: TextButton(
                onPressed: () {
                  setSheetState(() {
                    tempQuality = null;
                    tempFormat = null;
                    tempMetadata = null;
                    tempSortMode = 'latest';
                  });
                },
                child: Text(context.l10n.libraryFilterReset),
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.libraryFilterQuality,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        AppChoiceChip(
                          label: Text(context.l10n.libraryFilterAll),
                          selected: tempQuality == null,
                          onSelected: (_) =>
                              setSheetState(() => tempQuality = null),
                        ),
                        AppChoiceChip(
                          label: Text(context.l10n.libraryFilterQualityHiRes),
                          selected: tempQuality == LibraryQualityFilter.hiRes,
                          onSelected: (_) => setSheetState(
                            () => tempQuality = LibraryQualityFilter.hiRes,
                          ),
                        ),
                        AppChoiceChip(
                          label: Text(context.l10n.libraryFilterQualityCD),
                          selected: tempQuality == LibraryQualityFilter.cd,
                          onSelected: (_) => setSheetState(
                            () => tempQuality = LibraryQualityFilter.cd,
                          ),
                        ),
                        AppChoiceChip(
                          label: Text(context.l10n.libraryFilterQualityLossy),
                          selected: tempQuality == LibraryQualityFilter.lossy,
                          onSelected: (_) => setSheetState(
                            () => tempQuality = LibraryQualityFilter.lossy,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Text(
                      context.l10n.libraryFilterFormat,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AppChoiceChip(
                          label: Text(context.l10n.libraryFilterAll),
                          selected: tempFormat == null,
                          onSelected: (_) =>
                              setSheetState(() => tempFormat = null),
                        ),
                        for (final format in libraryFormatFilterAliases.keys)
                          AppChoiceChip(
                            label: Text(switch (format) {
                              'm4a' => 'M4A / MP4',
                              'wv' => 'WavPack',
                              _ => format.toUpperCase(),
                            }),
                            selected: tempFormat == format,
                            onSelected: (_) =>
                                setSheetState(() => tempFormat = format),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Text(
                      context.l10n.libraryFilterMetadata,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        metadataChip(context.l10n.libraryFilterAll, null),
                        metadataChip(
                          context.l10n.libraryFilterMetadataComplete,
                          'complete',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataMissingAny,
                          'missing-any',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataMissingYear,
                          'missing-year',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataMissingGenre,
                          'missing-genre',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataMissingAlbumArtist,
                          'missing-album-artist',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataMissingTrackNumber,
                          'missing-track-number',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataMissingDiscNumber,
                          'missing-disc-number',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataMissingArtist,
                          'missing-artist',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataIncorrectIsrcFormat,
                          'incorrect-isrc-format',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataMissingIsrc,
                          'missing-isrc',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataMissingLabel,
                          'missing-label',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataMissingLyrics,
                          'missing-lyrics',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataHasReplayGain,
                          'has-replaygain',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataMissingReplayGain,
                          'missing-replaygain',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterIncompleteAlbums,
                          incompleteAlbumFilter,
                        ),
                        metadataChip(
                          context.l10n.libraryAlbumCompletenessUnknown,
                          unknownAlbumCompletenessFilter,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Text(
                      context.l10n.libraryFilterSort,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        sortChip(
                          context.l10n.libraryFilterSortLatest,
                          'latest',
                        ),
                        sortChip(
                          context.l10n.libraryFilterSortOldest,
                          'oldest',
                        ),
                        // Playlists have no file size of their own.
                        if (widget.librarySection != 'playlists') ...[
                          sortChip(
                            context.l10n.libraryFilterSortSizeLargest,
                            'size-desc',
                          ),
                          sortChip(
                            context.l10n.libraryFilterSortSizeSmallest,
                            'size-asc',
                          ),
                        ],
                        sortChip(context.l10n.searchSortTitleAZ, 'a-z'),
                        sortChip(context.l10n.searchSortTitleZA, 'z-a'),
                        sortChip(context.l10n.searchSortArtistAZ, 'artist-asc'),
                        sortChip(
                          context.l10n.searchSortArtistZA,
                          'artist-desc',
                        ),
                        sortChip(
                          context.l10n.libraryFilterSortAlbumAsc,
                          'album-asc',
                        ),
                        sortChip(
                          context.l10n.libraryFilterSortAlbumDesc,
                          'album-desc',
                        ),
                        sortChip(
                          context.l10n.searchSortDateNewest,
                          'release-newest',
                        ),
                        sortChip(
                          context.l10n.searchSortDateOldest,
                          'release-oldest',
                        ),
                        sortChip(
                          context.l10n.libraryFilterSortGenreAsc,
                          'genre-asc',
                        ),
                        sortChip(
                          context.l10n.libraryFilterSortGenreDesc,
                          'genre-desc',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: AppDialogAction(
                        filled: true,
                        onPressed: () {
                          _setState(() {
                            _filterQuality = tempQuality;
                            _filterFormat = tempFormat;
                            _filterMetadata = tempMetadata;
                            _sortMode = tempSortMode;
                            _resetLibraryPaging();
                          });
                          Navigator.pop(context);
                        },
                        child: Text(context.l10n.libraryFilterApply),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
