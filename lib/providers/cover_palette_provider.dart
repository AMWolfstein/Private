import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/services/cover_palette.dart';
import 'package:sistrum/providers/library_database_provider.dart';
import 'package:sistrum/services/library/cover_analysis_store.dart';

/// The app's cover palette cache: one analysis per cover version, shared by
/// every screen and background job. Tests override this provider.
final coverPaletteProvider = Provider<CoverPaletteCache>(
  (ref) => CoverPaletteCache(
    store: Platform.isAndroid
        ? LibraryCoverAnalysisStore(
            database: ref.read(libraryDatabaseProvider),
          )
        : null,
  ),
);

/// The shared cache for widgets built under the app's [ProviderScope].
CoverPaletteCache paletteOf(BuildContext context) =>
    ProviderScope.containerOf(
      context,
      listen: false,
    ).read(coverPaletteProvider);
