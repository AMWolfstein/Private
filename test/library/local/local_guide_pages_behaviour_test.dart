import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/screens/local_guide_pages.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/primitives/app_search_field.dart';

/// Hosts the guide pages the way the setup flow does: one page per swipe, with
/// the current index passed back into the builder.
class _GuideHost extends StatefulWidget {
  const _GuideHost({required this.firstIndex, this.initialPage = 0});

  final int firstIndex;
  final int initialPage;

  @override
  State<_GuideHost> createState() => _GuideHostState();
}

class _GuideHostState extends State<_GuideHost> {
  late int _current = widget.firstIndex + widget.initialPage;
  late final _controller = PageController(initialPage: widget.initialPage);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = buildLocalGuidePages(
      context,
      firstIndex: widget.firstIndex,
      currentIndex: _current,
    );
    return Scaffold(
      body: PageView(
        controller: _controller,
        onPageChanged: (page) =>
            setState(() => _current = widget.firstIndex + page),
        children: pages,
      ),
    );
  }
}

Future<void> _pumpHost(
  WidgetTester tester, {
  int firstIndex = 0,
  int initialPage = 0,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _GuideHost(firstIndex: firstIndex, initialPage: initialPage),
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

  testWidgets('the flow has five guide pages', (tester) async {
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
    expect(localGuidePageCount, 5);
  });

  testWidgets('the first page is the active search tutorial', (tester) async {
    await _pumpHost(tester);

    expect(find.text(en.tutorialSearchTitle), findsOneWidget);
    expect(find.text(en.tutorialSearchDesc), findsOneWidget);
    expect(_opacityOf(tester, en.tutorialSearchTitle), 1);
    expect(_opacityOf(tester, en.tutorialSearchDesc), 1);
  });

  testWidgets('swiping makes the next page the active one', (tester) async {
    await _pumpHost(tester);

    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(find.text(en.tutorialPlaybackTitle), findsOneWidget);
    expect(_opacityOf(tester, en.tutorialPlaybackTitle), 1);
    expect(find.text(en.tutorialPlaybackTip1), findsOneWidget);
    expect(find.text(en.tutorialPlaybackTip2), findsOneWidget);
    expect(find.text(en.tutorialPlaybackTip3), findsOneWidget);
  });

  testWidgets('the current index is offset by the first index of the flow', (
    tester,
  ) async {
    // The guide sits after other setup steps, so its first page is index 3.
    // Page 1 of the guide is then the active one.
    await _pumpHost(tester, firstIndex: 3, initialPage: 1);

    expect(find.text(en.tutorialPlaybackTitle), findsOneWidget);
    expect(_opacityOf(tester, en.tutorialPlaybackTitle), 1);
  });

  testWidgets(
    'the search tutorial reveals a result for typed text and hides it on clear',
    (tester) async {
      await _pumpHost(tester);
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

  testWidgets(
    'each page shows its tips and the last page shows the ready card',
    (tester) async {
      await _pumpHost(tester);
      final pages = <({String title, List<String> tips})>[
        (
          title: en.tutorialLibraryTitle,
          tips: [
            en.tutorialLibraryTip1,
            en.tutorialLibraryTip2,
            en.tutorialLibraryTip3,
          ],
        ),
        (
          title: en.tutorialStorageTitle,
          tips: [
            en.tutorialStorageTip1,
            en.tutorialStorageTip2,
            en.tutorialStorageTip3,
          ],
        ),
        (
          title: en.tutorialSettingsTitle,
          tips: [
            en.tutorialSettingsTip1,
            en.tutorialSettingsTip2,
            en.tutorialSettingsTip3,
          ],
        ),
      ];

      // Move past the playback page, then check each remaining page in turn.
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      for (final page in pages) {
        await tester.drag(find.byType(PageView), const Offset(-600, 0));
        await tester.pumpAndSettle();
        expect(find.text(page.title), findsOneWidget);
        expect(_opacityOf(tester, page.title), 1);
        for (final tip in page.tips) {
          expect(find.text(tip), findsOneWidget, reason: tip);
        }
      }

      expect(find.text(en.tutorialReadyMessage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
