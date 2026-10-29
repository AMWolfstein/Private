import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/models/track.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/widgets/primitives/app_action_button.dart';
import 'package:sistrum/widgets/sheets/playlist_picker_sheet.dart';

const _track = Track(
  id: 'example-track',
  name: 'Example track',
  artistName: 'Example artist',
  albumName: 'Example album',
  duration: 180,
);

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

class _Collections extends LibraryCollectionsNotifier {
  List<PlaylistPickerSummary> _summaries = [];
  final additions = <String>[];
  final createdNames = <String>[];
  final pendingAdditions = <Completer<void>>[];

  @override
  LibraryCollectionsState build() => LibraryCollectionsState(isLoaded: true);

  @override
  Future<String> createPlaylist(String name) async {
    createdNames.add(name);
    _summaries = [..._summaries, _playlist(name)];
    ref.invalidate(libraryPlaylistPickerSummariesProvider);
    return name;
  }

  @override
  Future<PlaylistAddBatchResult> addTracksToPlaylist(
    String playlistId,
    Iterable<Track> tracks, {
    bool preserveOccurrences = false,
  }) async {
    additions.add(playlistId);
    if (pendingAdditions.isNotEmpty) {
      await pendingAdditions.removeAt(0).future;
    }
    return PlaylistAddBatchResult(
      addedCount: tracks.length,
      alreadyInPlaylistCount: 0,
    );
  }
}

class _PopObserver extends NavigatorObserver {
  int pops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
  }
}

VoidCallback? _doneAction(WidgetTester tester, bool sistrum) => sistrum
    ? tester.widget<AppActionButton>(find.byType(AppActionButton)).onPressed
    : tester.widget<FilledButton>(find.byType(FilledButton)).onPressed;

PlaylistPickerSummary _playlist(String name, {bool contains = false}) =>
    PlaylistPickerSummary(
      id: name,
      name: name,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      trackCount: 2,
      containsAllRequestedTracks: contains,
    );

Widget _app(
  Widget child,
  _Collections collections, {
  required Brightness brightness,
  bool sistrum = true,
  double textScale = 1,
  List<NavigatorObserver> navigatorObservers = const [],
}) => ProviderScope(
  overrides: [
    settingsProvider.overrideWith(_Settings.new),
    libraryCollectionsProvider.overrideWith(() => collections),
    libraryPlaylistPickerSummariesProvider.overrideWith(
      (ref, request) async => collections._summaries,
    ),
  ],
  child: MaterialApp(
    navigatorObservers: navigatorObservers,
    theme: sistrum ? SistrumTheme.build(brightness) : ThemeData(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(body: child),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))).load();
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
  });

  for (final sistrum in [true]) {
    testWidgets('picker submits and closes once (Sistrum: $sistrum)', (
      tester,
    ) async {
      final addition = Completer<void>();
      final collections = _Collections()
        .._summaries = [_playlist('Road trip')]
        ..pendingAdditions.add(addition);
      final observer = _PopObserver();
      await tester.pumpWidget(
        _app(
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () =>
                  showAddTracksToPlaylistSheet(context, ref, [_track]),
              child: const Text('Open'),
            ),
          ),
          collections,
          brightness: Brightness.light,
          sistrum: sistrum,
          navigatorObservers: [observer],
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Road trip'));
      await tester.pump();
      final submit = _doneAction(tester, sistrum)!;
      // A repeated callback can arrive before the disabled button is rebuilt.
      submit();
      submit();
      await tester.pump();
      expect(collections.additions, ['Road trip']);
      expect(_doneAction(tester, sistrum), isNull);
      expect(observer.pops, 0);

      addition.complete();
      await tester.pump();
      // The route remains mounted while its closing animation runs.
      submit();
      await tester.pumpAndSettle();
      expect(collections.additions, ['Road trip']);
      expect(observer.pops, 1);
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('picker retains selections after failure (Sistrum: $sistrum)', (
      tester,
    ) async {
      final firstAddition = Completer<void>()..complete();
      final secondAddition = Completer<void>();
      final collections = _Collections()
        .._summaries = [_playlist('Road trip'), _playlist('Evening music')]
        ..pendingAdditions.addAll([firstAddition, secondAddition]);
      final observer = _PopObserver();
      await tester.pumpWidget(
        _app(
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () =>
                  showAddTracksToPlaylistSheet(context, ref, [_track]),
              child: const Text('Open'),
            ),
          ),
          collections,
          brightness: Brightness.light,
          sistrum: sistrum,
          navigatorObservers: [observer],
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Road trip'));
      await tester.tap(find.text('Evening music'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(collections.additions, ['Road trip', 'Evening music']);
      secondAddition.completeError(StateError('write failed'));
      await tester.pump();
      expect(observer.pops, 0);
      expect(_doneAction(tester, sistrum), isNotNull);

      // Retrying keeps the failed selection and skips the persisted playlist.
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(collections.additions, [
        'Road trip',
        'Evening music',
        'Evening music',
      ]);
      expect(observer.pops, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('picker adds only new selections (Sistrum: $sistrum)', (
      tester,
    ) async {
      final collections = _Collections()
        .._summaries = [
          _playlist('Already included', contains: true),
          _playlist('Road trip'),
          _playlist('Unselected playlist'),
        ];
      await tester.pumpWidget(
        _app(
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () =>
                  showAddTracksToPlaylistSheet(context, ref, [_track]),
              child: const Text('Open'),
            ),
          ),
          collections,
          brightness: Brightness.light,
          sistrum: sistrum,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Already included'));
      await tester.tap(find.text('Road trip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(collections.additions, ['Road trip']);
      expect(tester.takeException(), isNull);
    });
  }
}
