import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/track.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/library_search_provider.dart';
import 'package:sistrum/providers/local_home_feed_provider.dart';
import 'package:sistrum/providers/library_browse_provider.dart';
import 'package:sistrum/screens/home/home_tab.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/widgets/library_search_results.dart';

/// PERF-603: a Loved toggle or playlist edit must not rebuild the whole Home
/// feed. The dirty-rebuild log names every rebuilt widget, so HomeTab should
/// be absent after an unrelated collection change.
class _Local extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() => LocalLibraryState();
}

void main() {
  testWidgets('a Loved toggle does not rebuild HomeTab', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryCollectionsProvider.overrideWith(_Collections.new),
          localLibraryProvider.overrideWith(_Local.new),
          localHomeTracksProvider.overrideWith((ref) async => const []),
          libraryBrowsePageLoaderProvider.overrideWithValue(
            (request) async => const LibraryBrowsePage([]),
          ),
        ],
        child: MaterialApp(
          theme: SistrumTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HomeTab(mode: HomeTabMode.browse),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeTab)),
    );
    final rebuildLog = <String>[];
    debugPrintRebuildDirtyWidgets = true;
    final savedDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      rebuildLog.add(message ?? '');
    };

    var homeRebuilds = 0;
    try {
      (container.read(libraryCollectionsProvider.notifier) as _Collections)
          .bumpLoved();
      await tester.pump();
      await tester.pumpAndSettle();
      // Rebuilding the playlists list itself is fine; the feed is not.
      homeRebuilds = rebuildLog
          .where((line) => line.contains('HomeTab'))
          .length;
    } finally {
      debugPrintRebuildDirtyWidgets = false;
      debugPrint = savedDebugPrint;
    }
    // A positive control: the toggle must dirty at least one widget, or an
    // inert debug log would make the HomeTab count meaningless.
    expect(rebuildLog, isNotEmpty);
    expect(homeRebuilds, 0);
  });

  testWidgets('backspacing to the committed query cancels the stale debounce', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryCollectionsProvider.overrideWith(_Collections.new),
          localHomeTracksProvider.overrideWith((ref) async => const []),
          librarySearchProvider.overrideWith((ref, request) async => const []),
          libraryBrowsePageLoaderProvider.overrideWithValue(
            (request) async => const LibraryBrowsePage([]),
          ),
        ],
        child: MaterialApp(
          theme: SistrumTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HomeTab(mode: HomeTabMode.search),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A completed debounce really shows results, so the negative case below
    // cannot pass just because search is inert in the harness.
    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(LibrarySearchResults), findsOneWidget);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(find.byType(LibrarySearchResults), findsNothing);

    // Type and immediately backspace: the first keystroke's timer must be
    // cancelled, or it applies "a" under an empty field.
    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(LibrarySearchResults), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _Collections extends LibraryCollectionsNotifier {
  @override
  LibraryCollectionsState build() =>
      LibraryCollectionsState(isLoaded: true, loved: const []);

  void bumpLoved() {
    state = state.copyWith(
      loved: [
        CollectionTrackEntry(
          key: 'k',
          track: Track(
            id: 'k',
            name: 'Song',
            artistName: 'Artist',
            albumName: 'Album',
            duration: 0,
          ),
          addedAt: DateTime(2026),
        ),
      ],
    );
  }
}
