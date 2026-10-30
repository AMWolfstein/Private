import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/widgets/settings/custom_font_setting.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('with no custom font the row invites one to be added', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: CustomFontSetting()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(CustomFontSetting)),
    );
    expect(find.text(l10n.appearanceCustomFont), findsOneWidget);
    expect(find.text(l10n.appearanceCustomFontSubtitle), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
