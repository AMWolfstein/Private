import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/screens/settings/metadata_separator_settings_page.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

void main() {
  testWidgets('settings subpages scroll their last row above floating chrome', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const inset = 150.0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWith(_Settings.new)],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppTheme()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => MediaQuery(
              // The shell's floating bar and mini player arrive as padding.
              data: MediaQuery.of(
                context,
              ).copyWith(padding: const EdgeInsets.only(bottom: inset)),
              child: const Stack(
                fit: StackFit.expand,
                children: [
                  MetadataSeparatorSettingsPage(),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: inset,
                    child: ColoredBox(color: Colors.black),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final rows = find.byType(SettingsItem);
    expect(rows, findsWidgets);
    expect(tester.getBottomRight(rows.last).dy, lessThanOrEqualTo(420 - inset));
    expect(tester.takeException(), isNull);
  });
}
