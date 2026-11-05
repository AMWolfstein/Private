import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/screens/settings/appearance/appearance_settings_selectors.dart';
import 'package:sistrum/services/display/display_refresh_rate.dart';

DisplayRefreshState _state({
  required int preferenceHz,
  required double activeHz,
}) => DisplayRefreshState.fromMap({
  'attached': true,
  'preferenceHz': preferenceHz,
  'activeModeId': 1,
  'activeModeHz': activeHz,
  'supportedRates': [60, 90, 120],
  'settled': true,
});

Future<List<int>> _pump(
  WidgetTester tester, {
  required int preferenceHz,
  required DisplayRefreshState state,
}) async {
  final picked = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: DisplayRefreshRateSelector(
          preferenceHz: preferenceHz,
          state: state,
          onChanged: picked.add,
        ),
      ),
    ),
  );
  return picked;
}

void main() {
  test('choices are System plus the supported rates', () {
    expect(displayRefreshChoices(0, [60, 90, 120]), [0, 60, 90, 120]);
    // A saved rate the display lacks stays visible.
    expect(displayRefreshChoices(144, [60, 120]), [0, 60, 120, 144]);
    expect(displayRefreshChoices(0, const []), [0]);
  });

  testWidgets('shows only supported rates and applies a tap', (tester) async {
    final picked = await _pump(
      tester,
      preferenceHz: 0,
      state: _state(preferenceHz: 0, activeHz: 60),
    );
    for (final label in ['System', '60 Hz', '90 Hz', '120 Hz']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('144 Hz'), findsNothing);
    await tester.tap(find.text('120 Hz').first);
    expect(picked, [120]);
  });

  testWidgets('a kept 60 Hz is never shown as the selected 120 Hz', (
    tester,
  ) async {
    await _pump(
      tester,
      preferenceHz: 120,
      state: _state(preferenceHz: 120, activeHz: 60),
    );
    expect(find.text('Selected: 120 Hz'), findsOneWidget);
    expect(
      find.text('Active display (reported by Android): 60 Hz'),
      findsOneWidget,
    );
    expect(
      find.text('Status: requested rate not currently active'),
      findsOneWidget,
    );
    expect(
      find.text('Status: Android reports the selected rate'),
      findsNothing,
    );
  });

  testWidgets('a matching report is shown as active', (tester) async {
    await _pump(
      tester,
      preferenceHz: 120,
      state: _state(preferenceHz: 120, activeHz: 120),
    );
    expect(
      find.text('Status: Android reports the selected rate'),
      findsOneWidget,
    );
  });
}
