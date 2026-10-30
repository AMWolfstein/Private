import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/library/playlist_name_dialog.dart';

/// Shows the dialog from a button and records its result.
Future<void> _openDialog(
  WidgetTester tester, {
  String? prefill,
  required void Function(String?) onResult,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => onResult(
                  await showPlaylistNameDialog(context, prefill: prefill),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a typed name is returned trimmed', (tester) async {
    String? result = 'unset';
    await _openDialog(tester, onResult: (value) => result = value);
    await tester.enterText(find.byType(TextFormField), '  Road trip  ');
    await tester.tap(
      find.text(
        AppLocalizations.of(tester.element(find.byType(Scaffold))).actionCreate,
      ),
    );
    await tester.pumpAndSettle();
    expect(result, 'Road trip');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a blank name is refused and the dialog stays open', (
    tester,
  ) async {
    String? result = 'unset';
    await _openDialog(tester, onResult: (value) => result = value);
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.tap(find.text(l10n.actionCreate));
    await tester.pumpAndSettle();
    expect(find.text(l10n.collectionPlaylistNameRequired), findsOneWidget);
    expect(result, 'unset');
  });

  testWidgets('cancel returns no name and closes without errors', (
    tester,
  ) async {
    String? result = 'unset';
    await _openDialog(tester, onResult: (value) => result = value);
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    await tester.tap(find.text(l10n.dialogCancel));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.byType(TextFormField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a prefill starts the field with the suggested name', (
    tester,
  ) async {
    await _openDialog(tester, prefill: 'Suggested', onResult: (_) {});
    expect(find.text('Suggested'), findsOneWidget);
  });
}
