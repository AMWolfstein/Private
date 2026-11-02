import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/library/library_sort_provider.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/core/models/track.dart';

/// Returns the IconButton itself so header actions share their glass capsule.
IconButton appLibrarySortButton(
  BuildContext context,
  WidgetRef ref, {
  String fallback = 'a-z',
  List<String> options = const ['a-z', 'z-a', 'latest', 'oldest'],
}) {
  final requested = ref.watch(librarySortProvider) ?? fallback;
  final selected = options.contains(requested) ? requested : fallback;
  return IconButton(
    tooltip: context.l10n.librarySortTitle,
    icon: const Icon(Icons.sort),
    onPressed: () async {
      final value = await showAppBottomSheet<String>(
        context: context,
        builder: (sheetContext) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mode in options)
                ListTile(
                  title: Text(_label(sheetContext, mode)),
                  trailing: selected == mode ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(sheetContext, mode),
                ),
            ],
          ),
        ),
      );
      if (!context.mounted || value == null) return;
      ref.read(librarySortProvider.notifier).select(value);
    },
  );
}

String _label(BuildContext context, String mode) => switch (mode) {
  'original' => context.l10n.librarySortOriginal,
  'a-z' => context.l10n.searchSortTitleAZ,
  'z-a' => context.l10n.searchSortTitleZA,
  'latest' => context.l10n.libraryFilterSortLatest,
  'oldest' => context.l10n.libraryFilterSortOldest,
  'size-desc' => context.l10n.libraryFilterSortSizeLargest,
  'size-asc' => context.l10n.libraryFilterSortSizeSmallest,
  'artist-asc' => context.l10n.searchSortArtistAZ,
  'artist-desc' => context.l10n.searchSortArtistZA,
  'album-asc' => context.l10n.libraryFilterSortAlbumAsc,
  'album-desc' => context.l10n.libraryFilterSortAlbumDesc,
  'release-newest' => context.l10n.searchSortDateNewest,
  'release-oldest' => context.l10n.searchSortDateOldest,
  'genre-asc' => context.l10n.libraryFilterSortGenreAsc,
  'genre-desc' => context.l10n.libraryFilterSortGenreDesc,
  _ => throw ArgumentError.value(mode, 'mode'),
};

const librarySongSortOptions = [
  'original',
  'a-z',
  'z-a',
  'latest',
  'oldest',
  'size-desc',
  'size-asc',
  'artist-asc',
  'artist-desc',
  'album-asc',
  'album-desc',
  'release-newest',
  'release-oldest',
  'genre-asc',
  'genre-desc',
];

/// Deterministic metadata order for local in-memory collections. Callers add
/// their own added-date order; file-size sorting belongs to the SQLite browser.
int compareLibraryTracks(Track a, Track b, String mode) {
  String text(Track t) => switch (mode) {
    'artist-asc' || 'artist-desc' => t.artistName,
    'album-asc' || 'album-desc' => t.albumName,
    'release-newest' || 'release-oldest' => t.releaseDate ?? '',
    'genre-asc' || 'genre-desc' => t.genre ?? '',
    _ => t.name,
  };
  final order = text(a).toLowerCase().compareTo(text(b).toLowerCase());
  final descending =
      mode == 'z-a' || mode.endsWith('-desc') || mode == 'release-newest';
  if (order != 0) return descending ? -order : order;
  final title = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  return title != 0 ? title : a.id.compareTo(b.id);
}
