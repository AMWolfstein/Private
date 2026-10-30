import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/models/library_collections.dart';
import 'package:sistrum/models/local_library_item.dart';

/// Builds the app's full pages. The app supplies the screens through
/// [appScreensProvider], so navigation and widgets never import them.
abstract interface class AppScreens {
  Widget artist({required String artistName, String? coverPath});

  Widget album({
    required String albumName,
    required String artistName,
    String? coverPath,
    required List<LocalLibraryItem> tracks,
  });

  /// A playlist or the Loved collection, by its library mode.
  Widget collectionTracks({
    required LibraryCollectionMode mode,
    String? playlistId,
  });

  /// The songs credited to one composer.
  Widget composerSongs({required String composerName});

  Widget nowPlaying();
}

final appScreensProvider = Provider<AppScreens>(
  (ref) => throw StateError('appScreensProvider has no screens installed'),
);

/// The installed screens for [context]'s app.
AppScreens appScreensOf(BuildContext context) =>
    ProviderScope.containerOf(context, listen: false).read(appScreensProvider);
