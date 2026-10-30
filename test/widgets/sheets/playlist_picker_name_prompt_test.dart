import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/sheets/playlist_picker_name_prompt.dart';

void main() {
  testWidgets('the picker prompt returns the name typed into it', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await promptPlaylistName(context, 'Mix');
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Mix'), findsOneWidget);

    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    await tester.enterText(find.byType(TextFormField), 'Evening');
    await tester.tap(find.text(l10n.actionCreate));
    await tester.pumpAndSettle();
    expect(result, 'Evening');
    expect(tester.takeException(), isNull);
  });
}
