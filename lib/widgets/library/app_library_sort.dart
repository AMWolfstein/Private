import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/library/library_sort_provider.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/core/models/track.dart';

/// Returns the IconButton itself so header actions share their capsule.
IconButton appLibrarySortButton(
  BuildContext context,
  WidgetRef ref, {
  bool fileSize = false,
  bool releaseDate = false,
}) {
  final options = [
    'a-z',
    'z-a',
    if (fileSize) ...['size-desc', 'size-asc'],
    if (releaseDate) ...['release-newest', 'release-oldest'],
  ];
  final requested = ref.watch(librarySortProvider);
  final selected = options.contains(requested) ? requested : 'a-z';
  return IconButton(
    tooltip: context.l10n.librarySortTitle,
    icon: const Icon(Icons.sort),
    onPressed: () async {
      final value = await showAppBottomSheet<String>(
        context: context,
        useRootNavigator: true,
        builder: (sheetContext) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mode in options)
                ListTile(
                  title: Text(switch (mode) {
                    'a-z' => 'A–Z',
                    'z-a' => 'Z–A',
                    'size-desc' =>
                      sheetContext.l10n.libraryFilterSortSizeLargest,
                    'size-asc' =>
                      sheetContext.l10n.libraryFilterSortSizeSmallest,
                    'release-newest' => sheetContext.l10n.searchSortDateNewest,
                    'release-oldest' => sheetContext.l10n.searchSortDateOldest,
                    _ => throw StateError('Unsupported order'),
                  }),
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

/// Compare the displayed title with a stable identity tie-breaker.
int compareLibraryTracks(Track a, Track b, String mode) {
  if (mode == 'release-newest' || mode == 'release-oldest') {
    final date = (a.releaseDate ?? '').compareTo(b.releaseDate ?? '');
    if (date != 0) return mode == 'release-newest' ? -date : date;
  }
  final order = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  if (order != 0) return mode == 'z-a' ? -order : order;
  return a.id.compareTo(b.id);
}
