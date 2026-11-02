import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/library/local_library_provider.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/screens/settings/library/library_settings_page.dart';
import 'package:sistrum/screens/settings/library/song_analysis_settings_page.dart';
import 'package:sistrum/screens/settings/settings_search_catalog.dart';
import 'package:sistrum/services/playback/autoplay/song_analysis.dart';
import 'package:sistrum/services/playback/music_player/music_player_runtime.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';

class _Analysis implements SongAnalysis {
  @override
  final progress = ValueNotifier<SongAnalysisProgress?>(
    const SongAnalysisProgress(analyzed: 2, total: 1983),
  );
  int clears = 0;
  AppSettings? configured;
  @override
  void configure(AppSettings settings) => configured = settings;
  @override
  Future<void> refreshProgress() async {}
  @override
  Future<void> clear() async {
    clears++;
    progress.value = SongAnalysisProgress(
      analyzed: 0,
      total: progress.value!.total,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Runtime implements MusicPlayerRuntime {
  _Runtime(this.songAnalysis);
  @override
  final SongAnalysis songAnalysis;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Library extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() => LocalLibraryState();
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'Local Library links analysis below described tag separators ($brightness)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(430, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final analysis = _Analysis();
        addTearDown(analysis.progress.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localLibraryProvider.overrideWith(_Library.new),
              musicPlayerRuntimeProvider.overrideWithValue(_Runtime(analysis)),
            ],
            child: MaterialApp(
              theme: AppTheme.build(brightness),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const LibrarySettingsPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final tags = find.byWidgetPredicate(
          (w) => w is SettingsItem && w.title == 'Tag separators',
        );
        final row = find.byWidgetPredicate(
          (w) => w is SettingsItem && w.title == 'Song analysis',
        );
        await tester.scrollUntilVisible(
          row,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.widget<SettingsItem>(tags).subtitle, isNotEmpty);
        expect(tester.widget<SettingsItem>(row).subtitle, isNotEmpty);
        expect(
          tester.getTopLeft(row).dy,
          greaterThan(tester.getTopLeft(tags).dy),
        );
        final l10n = AppLocalizations.of(tester.element(row));
        final catalog = SettingsSearchCatalog(l10n);
        expect(catalog.library.any((e) => e.title == l10n.songAnalysis), true);
        expect(
          catalog.playback.any((e) => e.title == l10n.autoplaySoundMatching),
          false,
        );
        await Scrollable.ensureVisible(tester.element(row), alignment: .4);
        await tester.pumpAndSettle();
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(find.byType(SongAnalysisSettingsPage), findsOneWidget);
        expect(find.text('Only while charging'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'analysis preferences persist, show progress and require confirmed clearing',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'app_settings': jsonEncode(
          const AppSettings(autoplaySoundMatching: true).toJson(),
        ),
      });
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final analysis = _Analysis();
      addTearDown(analysis.progress.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            musicPlayerRuntimeProvider.overrideWithValue(_Runtime(analysis)),
            localLibraryProvider.overrideWith(_Library.new),
          ],
          child: MaterialApp(
            theme: AppTheme.build(Brightness.dark),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SongAnalysisSettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(SongAnalysisSettingsPage)),
      );
      expect(find.text(l10n.songAnalysisProgress(2, 1983)), findsOneWidget);
      final charge = find.byWidgetPredicate(
        (w) => w is SettingsSwitchItem && w.title == 'Only while charging',
      );
      await tester.tap(charge);
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(loadBootstrapSettings(prefs).songAnalysisOnlyWhileCharging, false);
      expect(analysis.configured?.songAnalysisOnlyWhileCharging, false);
      final clear = find.byWidgetPredicate(
        (w) => w is SettingsItem && w.title == l10n.songAnalysisClear,
      );
      await tester.tap(clear);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(analysis.clears, 0);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(AppDialogAction, l10n.songAnalysisClear),
      );
      await tester.pumpAndSettle();
      expect(analysis.clears, 1);
      expect(find.text(l10n.songAnalysisProgress(0, 1983)), findsOneWidget);
      expect(loadBootstrapSettings(prefs).autoplaySoundMatching, true);
      final toggle = find.byWidgetPredicate(
        (w) => w is SettingsSwitchItem && w.title == l10n.songAnalysis,
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(loadBootstrapSettings(prefs).autoplaySoundMatching, false);
      expect(analysis.configured?.autoplaySoundMatching, false);
      analysis.progress.value = const SongAnalysisProgress(
        analyzed: 0,
        total: 0,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
