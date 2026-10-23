import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/screens/setup_screen.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();

  @override
  Future<void> ensureLoaded() async {}
}

const _backend = MethodChannel('com.zarz.spotiflac/backend');
const _device = MethodChannel('dev.fluttercommunity.plus/device_info');
const _permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
Widget _setup() {
  final router = GoRouter(
    initialLocation: '/setup',
    routes: [
      GoRoute(path: '/setup', builder: (_, _) => const SetupScreen()),
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('Home reached')),
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
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  late SharedPreferences prefs;
  var pickerCalls = 0;
  var sdkVersion = 33;
  var permissionRequests = 0;
  var audioGranted = true;
  var notificationsGranted = true;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    sdkVersion = 33;
    pickerCalls = permissionRequests = 0;
    audioGranted = notificationsGranted = true;
    messenger.setMockMethodCallHandler(
      _device,
      (_) async => {
        'version': {
          'sdkInt': sdkVersion,
          'release': '13',
          'codename': 'REL',
          'incremental': '1',
        },
        for (final key in [
          'board',
          'bootloader',
          'brand',
          'device',
          'display',
          'fingerprint',
          'hardware',
          'host',
          'id',
          'manufacturer',
          'model',
          'product',
          'tags',
          'type',
        ])
          key: 'test',
        'isPhysicalDevice': false,
        'time': 0,
        'isLowRamDevice': false,
        'freeDiskSize': 1000,
        'totalDiskSize': 2000,
        'physicalRamSize': 8000,
        'availableRamSize': 4000,
      },
    );
    messenger.setMockMethodCallHandler(_permissions, (call) async {
      if (call.method == 'checkPermissionStatus') {
        final granted = call.arguments == Permission.notification.value
            ? notificationsGranted
            : audioGranted;
        return granted
            ? PermissionStatus.granted.index
            : PermissionStatus.denied.index;
      }
      if (call.method == 'requestPermissions') permissionRequests++;
      throw StateError('Unexpected permission request: ${call.method}');
    });
    messenger.setMockMethodCallHandler(_backend, (call) async {
      if (call.method == 'pickSafTree') pickerCalls++;
      throw StateError(
        'Setup must not call the folder backend: ${call.method}',
      );
    });
  });

  tearDown(() {
    for (final channel in [_device, _permissions, _backend]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
  }

  for (final sdk in [32, 33]) {
    testWidgets(
      'one guide finishes on permissions without choosing an output folder (SDK $sdk)',
      (tester) async {
        sdkVersion = sdk;
        tester.view.physicalSize = const Size(430, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_setup());
        await tester.pumpAndSettle();
        final total = sdk >= 33 ? 8 : 7;
        expect(find.text('1/$total'), findsOneWidget);
        // The five playback tips share setup's page counter and Next/Back controls.
        for (var step = 0; step < 6; step++) {
          await next(tester);
          const guideTitles = [
            'Finding Music',
            'Local playback',
            'Your Library',
            'Music folders',
            'Customize Your Experience',
            'Storage Permission Required',
          ];
          expect(find.text(guideTitles[step]), findsOneWidget);
          expect(find.text('${step + 2}/$total'), findsOneWidget);
          expect(find.text('Select Folder'), findsNothing);
          expect(find.text('Choose music folder'), findsNothing);
        }
        expect(find.text('Storage Permission Granted!'), findsOneWidget);
        if (sdk >= 33) {
          await next(tester);
          expect(find.text('Notification Permission Granted!'), findsOneWidget);
        }
        expect(find.text('Get Started'), findsOneWidget);
        await tester.tap(find.text('Get Started'));
        await tester.pumpAndSettle();
        expect(find.text('Home reached'), findsOneWidget);
        final saved =
            jsonDecode(prefs.getString('app_settings')!)
                as Map<String, dynamic>;
        expect(saved['isFirstLaunch'], isFalse);
        expect(saved['hasCompletedTutorial'], isTrue);
        expect(prefs.getString('setup_progress_v1'), isNull);
        expect(pickerCalls, 0);
        expect(permissionRequests, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('merged guide can go back and resumes its saved tip', (
    tester,
  ) async {
    await prefs.setString('setup_progress_v1', '{"version":3,"step":2}');
    await tester.pumpWidget(_setup());
    await tester.pumpAndSettle();
    expect(find.text('3/8'), findsOneWidget);
    expect(find.text('Local playback'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('2/8'), findsOneWidget);
    expect(find.text('Finding Music'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_setup());
    await tester.pumpAndSettle();
    expect(find.text('2/8'), findsOneWidget);
    await next(tester);
    expect(find.text('3/8'), findsOneWidget);
    expect(pickerCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a draft saved with the language step resumes on the same tip', (
    tester,
  ) async {
    await prefs.setString('setup_progress_v1', '{"version":2,"step":3}');
    await tester.pumpWidget(_setup());
    await tester.pumpAndSettle();
    expect(find.text('3/8'), findsOneWidget);
    expect(find.text('Local playback'), findsOneWidget);
    expect(find.text('Choose Language'), findsNothing);
  });

  testWidgets('old folder-step draft resumes on the final permission page', (
    tester,
  ) async {
    await prefs.setString(
      'setup_progress_v1',
      '{"step":4,"directory":"Old downloads","treeUri":"obsolete"}',
    );
    await tester.pumpWidget(_setup());
    await tester.pumpAndSettle();
    expect(find.text('8/8'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('Old downloads'), findsNothing);
    expect(pickerCalls, 0);
  });

  testWidgets(
    'resume rechecks permissions and retains the unified guide step',
    (tester) async {
      await prefs.setString('setup_progress_v1', '{"step":2}');
      audioGranted = false;
      await tester.pumpWidget(_setup());
      await tester.pumpAndSettle();
      expect(find.text('Grant Permission'), findsOneWidget);
      expect(find.text('7/8'), findsOneWidget);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      audioGranted = true;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Storage Permission Granted!'), findsOneWidget);
      expect(permissionRequests, 0);
      expect(find.text('7/8'), findsOneWidget);
    },
  );

  testWidgets('skipped notifications survive restarting and finish directly', (
    tester,
  ) async {
    await prefs.setString('setup_progress_v1', '{"step":3}');
    notificationsGranted = false;
    await tester.pumpWidget(_setup());
    await tester.pumpAndSettle();
    expect(find.text('Get Started'), findsOneWidget);
    final button = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    final draft =
        jsonDecode(prefs.getString('setup_progress_v1')!)
            as Map<String, dynamic>;
    expect(draft['version'], 3);
    expect(draft['step'], 7);
    expect(draft.keys, isNot(contains('treeUri')));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_setup());
    await tester.pumpAndSettle();
    expect(find.text('8/8'), findsOneWidget);
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(find.text('Home reached'), findsOneWidget);
    expect(permissionRequests, 0);
  });
}
