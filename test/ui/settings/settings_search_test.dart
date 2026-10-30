import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/screens/settings/about_page.dart';
import 'package:sistrum/screens/settings/settings_tab.dart';
import 'package:sistrum/screens/settings/settings_search_catalog.dart';
import '../../support/material_test_theme.dart';
import 'package:sistrum/widgets/settings/settings_search_highlight.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: MaterialTestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SettingsTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('retired root keywords no longer advertise settings', (
    tester,
  ) async {
    await pumpSettings(tester);
    for (final query in ['amoled', 'layout', 'grid', 'provider']) {
      await tester.enterText(find.byType(TextField), query);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsItem), findsNothing, reason: query);
    }
  });

  testWidgets('new controls are searchable and have a highlight target', (
    tester,
  ) async {
    for (final query in ['glass clarity', 'custom font', 'text size']) {
      await pumpSettings(tester);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(SettingsTab)),
      );
      final label = switch (query) {
        'glass clarity' => l10n.appearanceGlassClarity,
        'custom font' => l10n.appearanceCustomFont,
        _ => l10n.lyricsTextSize,
      };
      await tester.enterText(find.byType(TextField), query);
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SettingsSearchTarget && widget.label == label,
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('USB sub-options are indexed only for Android audio', (
    tester,
  ) async {
    await pumpSettings(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(SettingsTab)));
    final android = SettingsSearchCatalog(l10n, androidAudio: true);
    final other = SettingsSearchCatalog(l10n);
    for (final label in [
      l10n.usbDsdOverPcm,
      l10n.usbFixedVolume,
      l10n.usbHardwareVolume,
    ]) {
      final entry = android.playback.singleWhere(
        (entry) => entry.title == label,
      );
      expect(entry.targetLabel, l10n.usbBitPerfect);
      expect(other.playback.any((entry) => entry.title == label), isFalse);
    }
  });

  testWidgets('retired download settings and player chooser are absent', (
    tester,
  ) async {
    await pumpSettings(tester);
    expect(find.text('Files & Folders'), findsNothing);
    expect(find.text('Metadata'), findsNothing);
    for (final query in [
      'Default view',
      'Audio quality',
      'History View',
      'Music folder',
      'Artist Tag Mode',
      'Embedded Cover Size',
      'External player',
      'Built-in preview player',
    ]) {
      await tester.enterText(find.byType(TextField), query);
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == query,
        ),
        findsNothing,
      );
    }
    await tester.enterText(find.byType(TextField), 'Scan');
    await tester.pumpAndSettle();
    expect(find.text('Scan Library'), findsWidgets);
  });

  testWidgets('finds the saved player view choice from Appearance', (
    tester,
  ) async {
    await pumpSettings(tester);
    await tester.enterText(find.byType(TextField), 'immersive');
    await tester.pumpAndSettle();
    expect(find.text('Player view'), findsOneWidget);
    await tester.tap(find.text('Player view'));
    await tester.pumpAndSettle();
    expect(find.text('Immersive view').hitTestable(), findsOneWidget);
    expect(find.text('History View'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('finds controls nested inside a settings page', (tester) async {
    await pumpSettings(tester);

    await tester.enterText(find.byType(TextField), 'replaygain');
    await tester.pump();

    expect(find.text('Volume normalization'), findsOneWidget);
    expect(find.text('Playback'), findsWidgets);
    expect(find.text('No settings found for "replaygain"'), findsNothing);
  });

  testWidgets(
    'returning from a search result does not restore keyboard focus',
    (tester) async {
      await pumpSettings(tester);

      final searchField = find.byType(TextField);
      await tester.tap(searchField);
      await tester.enterText(searchField, 'build number');
      await tester.pump();

      final focusedField = tester.widget<TextField>(searchField);
      expect(focusedField.focusNode?.hasFocus, isTrue);
      expect(find.text('Version'), findsOneWidget);

      await tester.tap(find.text('Version'));
      await tester.pumpAndSettle();
      expect(find.byType(AboutPage), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      final restoredField = tester.widget<TextField>(find.byType(TextField));
      expect(restoredField.focusNode?.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.text('Version'), findsOneWidget);
    },
  );

  testWidgets('search target scrolls into view with standard selected color', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: MaterialTestTheme.light(),
        home: SettingsSearchHighlightScope(
          targetLabel: 'Target setting',
          child: Scaffold(
            body: CustomScrollView(
              controller: scrollController,
              slivers: const [
                SliverToBoxAdapter(child: SizedBox(height: 1200)),
                SliverToBoxAdapter(
                  child: SettingsItem(title: 'Target setting'),
                ),
                SliverToBoxAdapter(child: SizedBox(height: 600)),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(scrollController.offset, greaterThan(0));
    final highlightFinder = find.byKey(
      const ValueKey('settings-highlight:Target setting'),
    );
    final highlighted = tester.widget<AnimatedContainer>(highlightFinder);
    final highlightedDecoration = highlighted.decoration! as BoxDecoration;
    final colorScheme = Theme.of(tester.element(highlightFinder)).colorScheme;
    expect(
      highlightedDecoration.color,
      colorScheme.primaryContainer.withValues(alpha: 0.3),
    );
    expect(highlightedDecoration.border, isNull);
    expect(highlightedDecoration.boxShadow, isNull);

    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump(const Duration(milliseconds: 400));
    final faded = tester.widget<AnimatedContainer>(highlightFinder);
    final fadedDecoration = faded.decoration! as BoxDecoration;
    expect(fadedDecoration.color, Colors.transparent);
  });
}
