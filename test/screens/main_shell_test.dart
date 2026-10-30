import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/screens/main_shell.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();

  @override
  Future<void> ensureLoaded() async {}
}

Widget _shell() {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const MainShell(preloadTabs: false),
      ),
    ],
  );
  addTearDown(router.dispose);
  return ProviderScope(
    overrides: [settingsProvider.overrideWith(_Settings.new)],
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('main shell mounts and settles without a Search preload', (
    tester,
  ) async {
    await tester.pumpWidget(_shell());
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.byType(MainShell), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
