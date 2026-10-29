import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/screens/settings/library_settings_page.dart';
import 'package:sistrum/services/library/library_database.dart';
import 'support/material_test_theme.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

class _Library extends LocalLibraryNotifier {
  _Library(this._initial, this._cleanup);

  final LocalLibraryState _initial;
  final Future<int> Function() _cleanup;

  @override
  LocalLibraryState build() => _initial;

  @override
  Future<int> cleanupMissingFiles({String? iosBookmark}) => _cleanup();

  void _beginScan() => state = state.copyWith(isScanning: true);
}

class _RetryLibrary extends _Library {
  _RetryLibrary()
    : super(
        LocalLibraryState(
          loadFailed: true,
          sources: const [
            LocalLibrarySource(
              id: 'sd-card',
              path: 'content://storage/tree/sd-card',
              displayName: 'Saved music',
              available: false,
            ),
          ],
        ),
        () async => 0,
      );

  int _reloadCalls = 0;

  @override
  Future<void> reloadFromStorage() async {
    _reloadCalls++;
    state = state.copyWith(loadFailed: false, totalCount: 5);
  }
}

Finder get _cleanupRow => find.byWidgetPredicate(
  (widget) => widget is SettingsItem && widget.title == 'Cleanup Missing Files',
);

Future<void> _mount(
  WidgetTester tester, {
  required bool sistrum,
  required _Library library,
  Size size = const Size(430, 1000),
  double textScale = 1,
  double? pageTextScale,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        localLibraryProvider.overrideWith(() => library),
      ],
      child: MaterialApp(
        theme: sistrum ? AppTheme.build(Brightness.dark) : MaterialTestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(pageTextScale ?? textScale),
            ),
            child: const LibrarySettingsPage(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Default view'), findsNothing);
  expect(find.text('Audio quality'), findsNothing);
  expect(find.text('Scan Settings'), findsOneWidget);
  await tester.scrollUntilVisible(find.text('Cleanup Missing Files'), 300);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Auto scan picker can scroll to the final option at 2x text', (
    tester,
  ) async {
    await _mount(
      tester,
      sistrum: true,
      library: _Library(LocalLibraryState(), () async => 0),
      size: const Size(360, 640),
      textScale: 2,
      // Isolate the modal contract from the existing hero timestamp overflow
      // (UX-245). The root-navigator sheet still inherits 2x below.
      pageTextScale: 1,
    );
    await tester.scrollUntilVisible(find.text('Auto Scan'), -200);
    await tester.tap(find.text('Auto Scan'));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    final l10n = AppLocalizations.of(tester.element(sheet));
    expect(MediaQuery.textScalerOf(tester.element(sheet)).scale(16), 32);
    final last = find.descendant(
      of: sheet,
      matching: find.text(l10n.libraryAutoScanWeekly),
    );
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    expect(last.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
  });

  for (final sistrum in [true]) {
    testWidgets('source shows the scan failure reason (Sistrum: $sistrum)', (
      tester,
    ) async {
      const error =
          'The previous library scan was interrupted. Scan again to continue.';
      final library = _Library(
        LocalLibraryState(
          totalCount: 1877,
          sources: const [
            LocalLibrarySource(
              id: 'music',
              path: '/music',
              displayName: 'Saved music',
              trackCount: 1877,
              lastScanError: error,
            ),
          ],
        ),
        () async => 0,
      );
      await _mount(tester, sistrum: sistrum, library: library);
      await tester.scrollUntilVisible(find.text('Saved music'), 200);
      await tester.pumpAndSettle();
      expect(find.textContaining(error), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('failed load shows saved folder and offers retry ($sistrum)', (
      tester,
    ) async {
      final library = _RetryLibrary();
      await _mount(tester, sistrum: sistrum, library: library);
      await tester.scrollUntilVisible(find.text('Retry'), -300);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Library could not be loaded'),
        findsOneWidget,
      );
      expect(find.text('Saved music'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(library._reloadCalls, 1);
      expect(find.textContaining('Library could not be loaded'), findsNothing);
      expect(find.text('Saved music'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cleanup removes missing local files ($sistrum)', (
      tester,
    ) async {
      final localDone = Completer<int>();
      var localCalls = 0;
      await _mount(
        tester,
        sistrum: sistrum,
        library: _Library(LocalLibraryState(totalCount: 1), () {
          localCalls++;
          return localDone.future;
        }),
      );
      expect(tester.widget<SettingsItem>(_cleanupRow).onTap, isNotNull);
      await tester.tap(find.text('Cleanup Missing Files'));
      await tester.pump();
      expect(localCalls, 1);
      expect(tester.widget<SettingsItem>(_cleanupRow).onTap, isNull);
      expect(
        find.descendant(
          of: _cleanupRow,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cleanup Missing Files'));
      await tester.pump();
      expect(localCalls, 1);
      localDone.complete(2);
      await tester.pumpAndSettle();
      expect(find.text('Removed 2 missing files from library'), findsOneWidget);
      expect(tester.widget<SettingsItem>(_cleanupRow).onTap, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cleanup reports errors and can retry ($sistrum)', (
      tester,
    ) async {
      var calls = 0;
      await _mount(
        tester,
        sistrum: sistrum,
        library: _Library(LocalLibraryState(totalCount: 1), () async {
          calls++;
          if (calls == 1) throw StateError('cleanup failed');
          return 1;
        }),
      );
      await tester.tap(find.text('Cleanup Missing Files'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Error:'), findsOneWidget);
      expect(tester.widget<SettingsItem>(_cleanupRow).onTap, isNotNull);
      await tester.tap(find.text('Cleanup Missing Files'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Removed 1 missing files from library'), findsOneWidget);
      expect(calls, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cleanup stays available for hidden source rows ($sistrum)', (
      tester,
    ) async {
      await _mount(
        tester,
        sistrum: sistrum,
        library: _Library(
          LocalLibraryState(
            sources: const [
              LocalLibrarySource(
                id: 'sd-card',
                path: 'content://storage/tree/sd-card',
                displayName: 'Music',
                available: false,
                trackCount: 5,
                isRemovable: true,
              ),
            ],
          ),
          () async => 0,
        ),
      );
      expect(tester.widget<SettingsItem>(_cleanupRow).onTap, isNotNull);
      await tester.tap(find.text('Cleanup Missing Files'));
      await tester.pumpAndSettle();
      expect(find.text('Removed 0 missing files from library'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cleanup cannot race an active scan ($sistrum)', (
      tester,
    ) async {
      var localCalls = 0;
      final library = _Library(LocalLibraryState(totalCount: 1), () async {
        localCalls++;
        return 0;
      });
      await _mount(tester, sistrum: sistrum, library: library);
      final originalTap = tester.widget<SettingsItem>(_cleanupRow).onTap!;
      library._beginScan();
      await tester.pump();
      expect(tester.widget<SettingsItem>(_cleanupRow).onTap, isNull);
      originalTap();
      await tester.pump();
      expect(localCalls, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
