import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/utils/logger.dart';

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

  _Settings.withLoader(Future<SharedPreferences> Function() load)
    : super(preferences: load);

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
    localLibraryEnabled: true,
    localLibraryPath: '/current',
    localLibraryBookmark: 'current-bookmark',
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
        'localLibraryPath': '/foreign',
        'localLibraryEnabled': false,
        'localLibraryBookmark': 'foreign',
        'localLibraryAutoScan': 'daily',
        'glassQuality': 'off',
      });
      final failed = expectLater(restore, throwsStateError);
      await prefs.whenStarted(0);
      expect(prefs.writes.single['isFirstLaunch'], isFalse);
      expect(prefs.writes.single['hasCompletedTutorial'], isTrue);
      expect(prefs.writes.single['localLibraryPath'], '/current');
      expect(prefs.writes.single['localLibraryAutoScan'], 'weekly');
      prefs.release(0).complete(false);
      await failed;
      expect(container.read(settingsProvider).glassQuality, 'auto');
      expect(container.read(settingsProvider).localLibraryPath, '/current');
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
      notifier.setLocalLibraryEnabled(true);
      await preferences.whenStarted(0);
      notifier.setLocalLibraryPathAndBookmark('content://test/tree/music', '');
      final finish = notifier.setFirstLaunchComplete();
      expect(container.read(settingsProvider).isFirstLaunch, isTrue);
      preferences.release(0).complete(true);
      await preferences.whenStarted(1);
      preferences.release(1).complete(true);
      await preferences.whenStarted(2);
      expect(preferences.writes.last['isFirstLaunch'], isFalse);
      expect(preferences.writes.last['hasCompletedTutorial'], isTrue);
      expect(
        preferences.writes.last['localLibraryPath'],
        'content://test/tree/music',
      );
      expect(container.read(settingsProvider).isFirstLaunch, isTrue);
      preferences.release(2).complete(true);
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
      notifier.setLocalLibraryPathAndBookmark('content://test/tree/latest', '');
      preferences.release(0).complete(true);
      await preferences.whenStarted(1);
      expect(container.read(settingsProvider).isFirstLaunch, isTrue);
      expect(preferences.writes.last['isFirstLaunch'], isFalse);
      expect(preferences.writes.last['hasCompletedTutorial'], isTrue);
      expect(
        preferences.writes.last['localLibraryPath'],
        'content://test/tree/latest',
      );
      preferences.release(1).complete(true);
      await finish;
      expect(container.read(settingsProvider).isFirstLaunch, isFalse);
      expect(container.read(settingsProvider).hasCompletedTutorial, isTrue);
      expect(
        container.read(settingsProvider).localLibraryPath,
        'content://test/tree/latest',
      );
    },
  );

  test('queued save callers await the complete coalescing drain', () async {
    final preferences = _Preferences();
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith(() => _Settings(preferences))],
    );
    addTearDown(container.dispose);
    final notifier = container.read(settingsProvider.notifier);
    final first = notifier.setGlassClarityLevel(1);
    await preferences.whenStarted(0);
    final second = notifier.setGlassClarityLevel(2);
    final third = notifier.setGlassClarityLevel(5);
    var firstCompleted = false;
    var secondCompleted = false;
    var thirdCompleted = false;
    unawaited(first.then((_) => firstCompleted = true));
    unawaited(second.then((_) => secondCompleted = true));
    unawaited(third.then((_) => thirdCompleted = true));
    await Future<void>.delayed(Duration.zero);
    expect(
      [firstCompleted, secondCompleted, thirdCompleted],
      [false, false, false],
    );

    preferences.release(0).complete(true);
    await preferences.whenStarted(1);
    expect(preferences.writes.length, 2);
    expect(preferences.writes.last['glassClarityLevel'], 5);
    expect(
      [firstCompleted, secondCompleted, thirdCompleted],
      [false, false, false],
    );
    preferences.release(1).complete(true);
    await Future.wait([first, second, third]);
    expect(
      [firstCompleted, secondCompleted, thirdCompleted],
      [true, true, true],
    );
    expect(preferences.writes.length, 2);
  });

  test(
    'failed active save keeps logged-error API and releases its owner',
    () async {
      final preferences = _Preferences();
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(() => _Settings(preferences)),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(settingsProvider.notifier);
      final first = notifier.setGlassClarityLevel(1);
      await preferences.whenStarted(0);
      final queued = notifier.setGlassClarityLevel(3);
      preferences.release(0).completeError(StateError('settings_save_failed'));
      await Future.wait([first, queued]);
      expect(
        LogBuffer().entries.any(
          (entry) =>
              entry.tag == 'SettingsProvider' &&
              entry.message.contains('settings_save_failed'),
        ),
        isTrue,
      );

      final retry = notifier.setGlassClarityLevel(4);
      await preferences.whenStarted(1);
      expect(preferences.writes.last['glassClarityLevel'], 4);
      preferences.release(1).complete(true);
      await retry;
    },
  );

  test(
    'synchronous preference failure does not retain a finished drain',
    () async {
      final preferences = _Preferences();
      var loads = 0;
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            () => _Settings.withLoader(() {
              if (loads++ == 0) throw StateError('settings_preferences_failed');
              return Future.value(preferences);
            }),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setGlassClarityLevel(1);
      expect(preferences.writes, isEmpty);

      final retry = notifier.setGlassClarityLevel(4);
      await preferences.whenStarted(0);
      expect(loads, 2);
      expect(preferences.writes.single['glassClarityLevel'], 4);
      preferences.release(0).complete(true);
      await retry;
    },
  );
}
