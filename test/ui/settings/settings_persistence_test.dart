import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';

class _Preferences implements SharedPreferences {
  final writes = <Map<String, dynamic>>[];
  final _started = <int, Completer<void>>{};
  final _released = <int, Completer<bool>>{};

  Future<void> whenStarted(int index) =>
      (_started[index] ??= Completer<void>()).future;

  Completer<bool> release(int index) => _released[index] ??= Completer<bool>();

  @override
  Future<bool> setString(String key, String value) {
    expect(key, 'app_settings');
    final index = writes.length;
    writes.add(jsonDecode(value) as Map<String, dynamic>);
    (_started[index] ??= Completer<void>()).complete();
    return release(index).future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends SettingsNotifier {
  _Settings(_Preferences preferences)
    : super(preferences: () async => preferences);

  @override
  AppSettings build() => const AppSettings();

  @override
  Future<void> ensureLoaded() async {}
}

class _ConfiguredSettings extends _Settings {
  _ConfiguredSettings(super.preferences);
  @override
  AppSettings build() => const AppSettings(
    isFirstLaunch: false,
    hasCompletedTutorial: true,
    localLibraryAutoScan: 'weekly',
  );
}

void main() {
  test(
    'restore retains installation state and reports failed persistence',
    () async {
      final prefs = _Preferences();
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(() => _ConfiguredSettings(prefs)),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(settingsProvider.notifier);
      final restore = notifier.restoreFromBackup({
        'isFirstLaunch': true,
        'hasCompletedTutorial': false,
        'localLibraryAutoScan': 'daily',
        'glassQuality': 'off',
      });
      final failed = expectLater(restore, throwsStateError);
      await prefs.whenStarted(0);
      expect(prefs.writes.single['isFirstLaunch'], isFalse);
      expect(prefs.writes.single['hasCompletedTutorial'], isTrue);
      expect(prefs.writes.single['localLibraryAutoScan'], 'weekly');
      prefs.release(0).complete(false);
      await failed;
      expect(
        container.read(settingsProvider).toJson(),
        isNot(contains('glassQuality')),
      );
      expect(container.read(settingsProvider).localLibraryAutoScan, 'weekly');
    },
  );

  test(
    'setup completes only after settings and both completion flags are durable',
    () async {
      final preferences = _Preferences();
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(() => _Settings(preferences)),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(settingsProvider.notifier);
      notifier.setLocale('de');
      final finish = notifier.setFirstLaunchComplete();
      expect(container.read(settingsProvider).isFirstLaunch, isTrue);
      preferences.release(0).complete(true);
      await preferences.whenStarted(1);
      expect(preferences.writes.last['isFirstLaunch'], isFalse);
      expect(preferences.writes.last['hasCompletedTutorial'], isTrue);
      expect(preferences.writes.last['locale'], 'de');
      expect(container.read(settingsProvider).isFirstLaunch, isTrue);
      preferences.release(1).complete(true);
      await finish;
      expect(container.read(settingsProvider).isFirstLaunch, isFalse);
      expect(container.read(settingsProvider).hasCompletedTutorial, isTrue);
    },
  );

  test('failed setup persistence keeps the user in setup', () async {
    final preferences = _Preferences();
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith(() => _Settings(preferences))],
    );
    addTearDown(container.dispose);
    final notifier = container.read(settingsProvider.notifier);
    final finish = notifier.setFirstLaunchComplete();
    final failed = expectLater(finish, throwsStateError);
    await preferences.whenStarted(0);
    preferences.release(0).complete(false);
    await failed;
    expect(container.read(settingsProvider).isFirstLaunch, isTrue);
  });

  test(
    'settings changed during setup completion cannot overwrite its flag',
    () async {
      final preferences = _Preferences();
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(() => _Settings(preferences)),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(settingsProvider.notifier);
      final finish = notifier.setFirstLaunchComplete();
      await preferences.whenStarted(0);
      notifier.setLocale('fr');
      preferences.release(0).complete(true);
      await preferences.whenStarted(1);
      expect(container.read(settingsProvider).isFirstLaunch, isTrue);
      expect(preferences.writes.last['isFirstLaunch'], isFalse);
      expect(preferences.writes.last['hasCompletedTutorial'], isTrue);
      expect(preferences.writes.last['locale'], 'fr');
      preferences.release(1).complete(true);
      await finish;
      expect(container.read(settingsProvider).isFirstLaunch, isFalse);
      expect(container.read(settingsProvider).hasCompletedTutorial, isTrue);
      expect(container.read(settingsProvider).locale, 'fr');
    },
  );
}
