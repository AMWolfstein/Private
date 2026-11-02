import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/library/library_sort_provider.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/core/models/track.dart';

/// Returns the IconButton itself so header actions share their glass capsule.
IconButton appLibrarySortButton(BuildContext context, WidgetRef ref) {
  final selected = ref.watch(librarySortProvider);
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
              for (final mode in const ['a-z', 'z-a'])
                ListTile(
                  title: Text(mode == 'a-z' ? 'A–Z' : 'Z–A'),
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
  final order = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  if (order != 0) return mode == 'z-a' ? -order : order;
  return a.id.compareTo(b.id);
}
