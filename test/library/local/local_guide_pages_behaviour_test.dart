import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/screens/setup/local_guide_pages.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/primitives/app_search_field.dart';

/// Hosts the guide page the way the setup flow does: the page is built with
/// the setup's current index, so it is active only when that index matches.
Future<void> _pumpGuide(
  WidgetTester tester, {
  int firstIndex = 0,
  int currentIndex = 0,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: buildLocalGuidePages(
              context,
              firstIndex: firstIndex,
              currentIndex: currentIndex,
            ).single,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opacity of the animated title or description that carries [text].
double _opacityOf(WidgetTester tester, String text) {
  final animated = find.ancestor(
    of: find.text(text),
    matching: find.byType(AnimatedOpacity),
  );
  return tester.widget<AnimatedOpacity>(animated.first).opacity;
}

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  testWidgets('the local guide is one setup page', (tester) async {
    late int count;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            count = buildLocalGuidePages(
              context,
              firstIndex: 0,
              currentIndex: 0,
            ).length;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(count, localGuidePageCount);
    expect(localGuidePageCount, 1);
  });

  testWidgets('the guide title and description are shown when active', (
    tester,
  ) async {
    await _pumpGuide(tester);

    expect(find.text(en.tutorialGuideTitle), findsOneWidget);
    expect(find.text(en.tutorialGuideDesc), findsOneWidget);
    expect(_opacityOf(tester, en.tutorialGuideTitle), 1);
    expect(_opacityOf(tester, en.tutorialGuideDesc), 1);
  });

  testWidgets('the guide is hidden while another setup step is current', (
    tester,
  ) async {
    await _pumpGuide(tester, firstIndex: 2, currentIndex: 0);

    expect(_opacityOf(tester, en.tutorialGuideTitle), 0);
    expect(_opacityOf(tester, en.tutorialGuideDesc), 0);
  });

  testWidgets(
    'the search example reveals a result for typed text and hides it on clear',
    (tester) async {
      await _pumpGuide(tester);
      final field = find.descendant(
        of: find.byType(AppSearchField),
        matching: find.byType(TextField),
      );
      expect(find.byIcon(Icons.music_note_rounded), findsNothing);

      await tester.enterText(field, 'Song');
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);

      await tester.tap(find.byTooltip(en.dialogClear));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.music_note_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('every topic, its tips and the ready card are on the page', (
    tester,
  ) async {
    await _pumpGuide(tester);
    final topics = <({String title, String description, List<String> tips})>[
      (
        title: en.tutorialPlaybackTitle,
        description: en.tutorialPlaybackDesc,
        tips: [
          en.tutorialPlaybackTip1,
          en.tutorialPlaybackTip2,
          en.tutorialPlaybackTip3,
        ],
      ),
      (
        title: en.tutorialLibraryTitle,
        description: en.tutorialLibraryDesc,
        tips: [
          en.tutorialLibraryTip1,
          en.tutorialLibraryTip2,
          en.tutorialLibraryTip3,
        ],
      ),
      (
        title: en.tutorialStorageTitle,
        description: en.tutorialStorageDesc,
        tips: [
          en.tutorialStorageTip1,
          en.tutorialStorageTip2,
          en.tutorialStorageTip3,
        ],
      ),
      (
        title: en.tutorialSettingsTitle,
        description: en.tutorialSettingsDesc,
        tips: [
          en.tutorialSettingsTip1,
          en.tutorialSettingsTip2,
          en.tutorialSettingsTip3,
        ],
      ),
    ];

    expect(find.text(en.tutorialSearchTitle), findsOneWidget);
    expect(find.text(en.tutorialSearchDesc), findsOneWidget);
    for (final topic in topics) {
      expect(find.text(topic.title), findsOneWidget);
      expect(find.text(topic.description), findsOneWidget);
      for (final tip in topic.tips) {
        expect(find.text(tip), findsOneWidget, reason: tip);
      }
    }
    expect(find.text(en.tutorialReadyMessage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
