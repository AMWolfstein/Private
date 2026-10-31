import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/providers/library/library_browse_provider.dart';
import 'package:sistrum/providers/library/library_collections_provider.dart';
import 'package:sistrum/providers/library/local_library_provider.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/screens/home/home_tab.dart';
import 'package:sistrum/core/theme/app_theme.dart';

/// Shared harness for widget tests of the Home feed (`HomeTab`).
class HomeSettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

class HomeLocalLibrary extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() => LocalLibraryState();
}

class HomeCollections extends LibraryCollectionsNotifier {
  @override
  LibraryCollectionsState build() => LibraryCollectionsState(isLoaded: true);
}

/// A release shelf entry with no cover art, so the card shows its fallback.
LibraryBrowseEntry bareRelease(String name) => LibraryBrowseEntry(
  source: 'local',
  key: name.toLowerCase(),
  name: name,
  artist: 'Local artist',
  samplePath: '',
  trackCount: 4,
  releaseDate: '2026-10-18',
);

/// Pumps the browse Home with [loader] answering every shelf query.
Future<void> pumpHome(
  WidgetTester tester, {
  required Future<LibraryBrowsePage> Function(LibraryBrowsePageRequest) loader,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(360, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(HomeSettings.new),
        localLibraryProvider.overrideWith(HomeLocalLibrary.new),
        libraryCollectionsProvider.overrideWith(HomeCollections.new),
        localHomeTracksProvider.overrideWith((ref) async => const []),
        libraryBrowsePageLoaderProvider.overrideWithValue(loader),
      ],
      child: MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomeTab(mode: HomeTabMode.browse),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
