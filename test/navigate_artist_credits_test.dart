import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/navigation/app_screens.dart';
import 'package:sistrum/navigation/detail_navigation.dart';
import 'package:sistrum/services/library/library_tag_credits.dart';

import 'support/material_test_theme.dart';

class _Screens implements AppScreens {
  @override
  Widget artist({required String artistName, String? coverPath}) =>
      Scaffold(body: Text('Page $artistName'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpOpener(
  WidgetTester tester, {
  required String artistNames,
  TagCreditRules rules = const TagCreditRules(),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appScreensProvider.overrideWithValue(_Screens())],
      child: MaterialApp(
        theme: MaterialTestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => navigateToArtistCredits(
                  context,
                  artistNames: artistNames,
                  rules: rules,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a single artist opens its page directly', (tester) async {
    await _pumpOpener(tester, artistNames: 'Solo');
    expect(find.text('Page Solo'), findsOneWidget);
  });

  testWidgets('several credits open a picker and the chosen artist', (
    tester,
  ) async {
    await _pumpOpener(tester, artistNames: 'A, B');
    expect(find.widgetWithText(ListTile, 'A'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'B'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'B'));
    await tester.pumpAndSettle();
    expect(find.text('Page B'), findsOneWidget);
  });

  testWidgets('a kept-together credit opens the whole name directly', (
    tester,
  ) async {
    await _pumpOpener(
      tester,
      artistNames: 'A, B',
      rules: const TagCreditRules(keepTogether: ['A, B']),
    );
    expect(find.text('Page A, B'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'A'), findsNothing);
  });
}
