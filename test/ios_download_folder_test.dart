import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/screens/setup_screen.dart';

class _SetupSettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();

  @override
  Future<void> ensureLoaded() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const backend = MethodChannel('com.zarz.spotiflac/backend');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Completer<Map<String, String>?> picker;
  late SharedPreferences prefs;
  var pickerCalls = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    pickerCalls = 0;
    messenger.setMockMethodCallHandler(backend, (call) async {
      expect(call.method, 'pickIosDirectory');
      pickerCalls++;
      return picker.future;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(backend, null);
  });

  testWidgets('setup retains the chosen folder and its grant in the draft', (
    tester,
  ) async {
    picker = Completer<Map<String, String>?>();
    const permissions = MethodChannel(
      'flutter.baseflow.com/permissions/methods',
    );
    messenger.setMockMethodCallHandler(permissions, (_) async => 1);
    addTearDown(() => messenger.setMockMethodCallHandler(permissions, null));
    await prefs.setString('setup_progress_v1', '{"step":3}');
    tester.view.physicalSize = const Size(820, 1180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWith(_SetupSettings.new)],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SetupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Select Folder'), findsOneWidget);
    await tester.tap(find.text('Select Folder'));
    // Setup keeps its loading indicator active while the options sheet is open.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Choose from Files'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(pickerCalls, 1);
    const path =
        '/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Music';
    picker.complete({'path': path, 'bookmark': 'native-access-bookmark'});
    await tester.pumpAndSettle();
    final draft = jsonDecode(prefs.getString('setup_progress_v1')!) as Map;
    expect(draft['directory'], path);
    expect(draft['bookmark'], 'native-access-bookmark');
    expect(draft['step'], 3);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
