import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/screens/settings/tag_separator_settings_page.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final sistrum in [true]) {
    for (final size in [const Size(390, 844), const Size(844, 390)]) {
      testWidgets('separator preview, save, cancel and reset ($sistrum, $size)', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final container = ProviderContainer(
          overrides: [settingsProvider.overrideWith(_Settings.new)],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(extensions: [if (sistrum) const AppTheme()]),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const TagSeparatorSettingsPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> tap(String text) async {
          // The save-time rows sit below the read-side sections on the page,
          // and the scroll view builds them only once they are close.
          final row = find.text(text);
          for (var i = 0; i < 40 && row.evaluate().isEmpty; i++) {
            await tester.drag(
              find.byType(CustomScrollView).first,
              const Offset(0, -200),
            );
            await tester.pump();
          }
          await tester.pumpAndSettle();
          await tester.ensureVisible(row.last);
          await tester.pumpAndSettle();
          await tester.tap(row.last);
          await tester.pumpAndSettle();
        }

        await tap('Artist');
        expect(find.byType(AppSheetHandle).hitTestable(), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AppBottomSheet),
            matching: find.byType(SettingsGroup),
          ),
          findsOneWidget,
        );
        await tap('Semicolon (;)');
        expect(find.text('Artist A; Artist B'), findsOneWidget);
        await tap('Save');
        expect(
          container.read(settingsProvider).metadataSeparators.artist,
          '; ',
        );
        expect(container.read(settingsProvider).metadataSeparators.genre, '');
        await tap('Artist');
        await tap('Custom separator');
        // The page also has delimiter fields; the sheet's field is the last one.
        await tester.enterText(find.byType(TextField).last, ' | ');
        await tester.pumpAndSettle();
        tester.view.viewInsets = FakeViewPadding(
          bottom: size.height > size.width ? 300 : 150,
        );
        await tester.pumpAndSettle();
        expect(find.byType(AppSheetHandle).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(find.text('Artist A | Artist B'), findsOneWidget);
        await tap('Save');
        tester.view.viewInsets = const FakeViewPadding();
        await tester.pumpAndSettle();
        expect(
          container.read(settingsProvider).metadataSeparators.artist,
          ' | ',
        );
        await tap('Artist');
        await tap('Slash (/)');
        // Dismissing a draft must not overwrite the saved preference.
        await tester.fling(
          find.byType(AppSheetHandle),
          Offset(0, size.height * 0.6),
          1200,
        );
        await tester.pumpAndSettle();
        expect(
          container.read(settingsProvider).metadataSeparators.artist,
          ' | ',
        );
        await tap('Artist');
        await tap('Keep source formatting');
        await tap('Save');
        expect(
          container.read(settingsProvider).metadataSeparators.isDefault,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
