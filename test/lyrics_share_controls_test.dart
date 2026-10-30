import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/screens/lyrics_share_card.dart';
import 'package:sistrum/screens/lyrics_share_controls.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first));

void main() {
  testWidgets('the background picker offers four backgrounds by name', (
    tester,
  ) async {
    await _pump(
      tester,
      BackgroundPicker(value: LyricsCardBackground.artwork, onChanged: (_) {}),
    );
    final l10n = _l10n(tester);
    expect(find.byTooltip(l10n.lyricsShareBackgroundArtwork), findsOneWidget);
    expect(find.byTooltip(l10n.lyricsShareBackgroundColor), findsOneWidget);
    expect(find.byTooltip(l10n.lyricsShareBackgroundDark), findsOneWidget);
    expect(find.byTooltip(l10n.lyricsShareBackgroundLight), findsOneWidget);
  });

  testWidgets('tapping a background reports that choice', (tester) async {
    LyricsCardBackground? chosen;
    await _pump(
      tester,
      BackgroundPicker(
        value: LyricsCardBackground.artwork,
        onChanged: (value) => chosen = value,
      ),
    );
    await tester.tap(find.byTooltip(_l10n(tester).lyricsShareBackgroundDark));
    await tester.pump();
    expect(chosen, LyricsCardBackground.dark);
  });

  testWidgets('the selection count shows how many lines are chosen', (
    tester,
  ) async {
    await _pump(tester, const SelectionCount(count: 2));
    expect(find.text('2/$lyricsShareMaxLines'), findsOneWidget);
  });

  testWidgets('a line choice shows its text and its selection state', (
    tester,
  ) async {
    var taps = 0;
    await _pump(
      tester,
      LineChoice(
        line: (text: 'Ready or not', background: false),
        selected: true,
        first: true,
        last: true,
        onTap: () => taps++,
      ),
    );
    expect(find.text('Ready or not'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.tap(find.text('Ready or not'));
    await tester.pump();
    expect(taps, 1);
  });
}
