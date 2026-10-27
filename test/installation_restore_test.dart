import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/app.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const backendChannel = MethodChannel('com.amwolfstein.sistrum/backend');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backendChannel, null);
  });

  test(
    'bootstrap completes legacy onboarding before the first route',
    () async {
      SharedPreferences.setMockInitialValues({
        'app_settings': '{"isFirstLaunch":false}',
      });
      final prefs = await SharedPreferences.getInstance();
      final settings = loadBootstrapSettings(prefs);
      expect(settings.hasCompletedTutorial, isTrue);
      expect(
        initialLocationForAppState(
          isFirstLaunch: settings.isFirstLaunch,
          hasCompletedTutorial: settings.hasCompletedTutorial,
        ),
        '/',
      );
    },
  );

  group('restored installation detection', () {
    test('fresh package plus persisted settings requires a reset', () {
      const installState = InstallationState(
        markerExisted: false,
        markerCreated: true,
        freshPackageInstall: true,
      );

      expect(
        shouldResetRestoredInstallation(
          hasPersistedSettings: true,
          installState: installState,
        ),
        isTrue,
      );
      expect(
        shouldResetRestoredInstallation(
          hasPersistedSettings: false,
          installState: installState,
        ),
        isFalse,
      );
    });

    test('normal upgrade without the new marker preserves settings', () {
      const installState = InstallationState(
        markerExisted: false,
        markerCreated: true,
        freshPackageInstall: false,
      );

      expect(
        shouldResetRestoredInstallation(
          hasPersistedSettings: true,
          installState: installState,
        ),
        isFalse,
      );
    });

    test('marker creation failure never triggers a repeated reset', () {
      const installState = InstallationState(
        markerExisted: false,
        markerCreated: false,
        freshPackageInstall: true,
      );

      expect(
        shouldResetRestoredInstallation(
          hasPersistedSettings: true,
          installState: installState,
        ),
        isFalse,
      );
    });

    test('subsequent launch with a marker preserves settings', () {
      const installState = InstallationState(
        markerExisted: true,
        markerCreated: true,
        freshPackageInstall: false,
      );

      expect(
        shouldResetRestoredInstallation(
          hasPersistedSettings: true,
          installState: installState,
        ),
        isFalse,
      );
    });
  });

  group('restored settings sanitization', () {
    const restored = AppSettings(
      keepScreenOnLyrics: false,
      locale: 'id',
      isFirstLaunch: false,
      localLibraryEnabled: true,
      localLibraryPath: 'content://tree/library',
      localLibraryBookmark: 'library-bookmark',
      localLibraryAutoScan: 'daily',
      hasCompletedTutorial: true,
    );

    test('resets installation-bound fields and keeps portable preferences', () {
      final sanitized = resetInstallationBoundSettings(restored);

      expect(sanitized.isFirstLaunch, isTrue);
      expect(sanitized.hasCompletedTutorial, isFalse);

      expect(sanitized.localLibraryEnabled, isFalse);
      expect(sanitized.localLibraryPath, isEmpty);
      expect(sanitized.localLibraryBookmark, isEmpty);
      expect(sanitized.localLibraryAutoScan, 'off');
      expect(sanitized.locale, restored.locale);
    });

    test('persists the sanitized state before bootstrap routing', () async {
      SharedPreferences.setMockInitialValues({
        'app_settings': jsonEncode(restored.toJson()),
      });
      final prefs = await SharedPreferences.getInstance();

      expect(hasPersistedAppSettings(prefs), isTrue);
      await resetRestoredInstallationSettings(prefs);
      final bootstrap = loadBootstrapSettings(prefs);

      expect(bootstrap.isFirstLaunch, isTrue);
    });
  });

  group('bootstrap routing', () {
    test('restored-install reset routes through the unified guide', () {
      final sanitized = resetInstallationBoundSettings(
        const AppSettings(isFirstLaunch: false, hasCompletedTutorial: true),
      );

      expect(
        initialLocationForAppState(
          isFirstLaunch: sanitized.isFirstLaunch,
          hasCompletedTutorial: sanitized.hasCompletedTutorial,
        ),
        '/setup',
      );
      expect(
        initialLocationForAppState(
          isFirstLaunch: false,
          hasCompletedTutorial: false,
        ),
        '/setup',
      );
      expect(
        initialLocationForAppState(
          isFirstLaunch: false,
          hasCompletedTutorial: true,
        ),
        '/',
      );
    });
  });

  group('strict SAF validation', () {
    test('returns the native persisted-grant result', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(backendChannel, (call) async {
            expect(call.method, 'isSafTreeAccessible');
            expect(
              (call.arguments as Map)['tree_uri'],
              'content://tree/missing',
            );
            return false;
          });

      expect(
        await PlatformBridge.validateSafTreeAccess('content://tree/missing'),
        isFalse,
      );
    });

    test('surfaces bridge errors instead of allowing an unverified write', () {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(backendChannel, (call) async {
            throw PlatformException(code: 'bridge_failure');
          });

      expect(
        PlatformBridge.validateSafTreeAccess('content://tree/missing'),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  test('Android backup policy excludes every app-data domain', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final currentRules = File(
      'android/app/src/main/res/xml/backup_rules.xml',
    ).readAsStringSync();
    final legacyRules = File(
      'android/app/src/main/res/xml/backup_rules_legacy.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:allowBackup="false"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/backup_rules"'),
    );
    expect(
      manifest,
      contains('android:fullBackupContent="@xml/backup_rules_legacy"'),
    );

    for (final domain in [
      'root',
      'file',
      'database',
      'sharedpref',
      'external',
      'device_root',
      'device_file',
      'device_database',
      'device_sharedpref',
    ]) {
      expect(currentRules, contains('domain="$domain" path="."'));
      expect(legacyRules, contains('domain="$domain" path="."'));
    }
    expect(currentRules, contains('<cloud-backup>'));
    expect(currentRules, contains('<device-transfer>'));
  });
}
