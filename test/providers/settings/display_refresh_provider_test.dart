import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/providers/settings/display_refresh_provider.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/services/display/display_refresh_rate.dart';

/// Stands in for the native controller: records every request and answers
/// with what a display that keeps 60 Hz would report.
class _FakeChannel extends DisplayRefreshRateChannel {
  final sent = <int>[];
  void Function(DisplayRefreshState)? onState;

  /// What the native controller pushes after an Activity attaches or the
  /// display changes.
  void push(Map<String, Object?> map) =>
      onState?.call(DisplayRefreshState.fromMap(map));

  @override
  Future<DisplayRefreshState> setPreference(int hz) async {
    sent.add(hz);
    return DisplayRefreshState.fromMap({
      'attached': true,
      'preferenceHz': hz,
      'requestedModeId': hz == 0 ? 0 : 3,
      'activeModeId': 1,
      'activeModeHz': 60.0,
      'supportedRates': [60, 90, 120],
    });
  }

  @override
  void setStateHandler(void Function(DisplayRefreshState)? onState) =>
      this.onState = onState;
}

class _Settings extends SettingsNotifier {
  _Settings(this.initial) : super(preferences: SharedPreferences.getInstance);
  final AppSettings initial;

  @override
  AppSettings build() => initial;

  @override
  Future<void> ensureLoaded() async {}
}

ProviderContainer _container(_FakeChannel channel, [int saved = 0]) {
  final container = ProviderContainer(
    overrides: [
      displayRefreshChannelProvider.overrideWithValue(channel),
      settingsProvider.overrideWith(
        () => _Settings(AppSettings(displayRefreshRate: saved)),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.listen(displayRefreshProvider, (_, _) {});
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the saved choice is sent at startup (a fresh launch)', () async {
    final channel = _FakeChannel();
    final container = _container(channel, 120);
    await pumpEventQueue();
    expect(channel.sent, [120]);
    expect(container.read(displayRefreshProvider).preferenceHz, 120);
  });

  test('System Default is sent as 0 so the request is cleared', () async {
    final channel = _FakeChannel();
    final container = _container(channel, 120);
    await pumpEventQueue();
    container.read(settingsProvider.notifier).setDisplayRefreshRate(0);
    await pumpEventQueue();
    expect(channel.sent, [120, 0]);
    expect(container.read(displayRefreshProvider).requestedModeId, 0);
  });

  test('a change applies at once and is saved', () async {
    final channel = _FakeChannel();
    final container = _container(channel);
    await pumpEventQueue();
    container.read(settingsProvider.notifier).setDisplayRefreshRate(90);
    await pumpEventQueue();
    expect(channel.sent, [0, 90]);
    final prefs = await SharedPreferences.getInstance();
    final json = jsonDecode(prefs.getString('app_settings')!) as Map;
    expect(json['displayRefreshRate'], 90);
  });

  test('a refused request leaves the saved choice untouched', () async {
    final channel = _FakeChannel();
    final container = _container(channel);
    await pumpEventQueue();
    container.read(settingsProvider.notifier).setDisplayRefreshRate(120);
    await pumpEventQueue();
    // The fake display stays at 60 Hz.
    final state = container.read(displayRefreshProvider);
    expect(state.activeModeHz, 60);
    expect(container.read(settingsProvider).displayRefreshRate, 120);
    expect(displayRefreshStatus(120, state), DisplayRefreshStatus.notApplied);
  });

  test('other settings changes send nothing', () async {
    final channel = _FakeChannel();
    final container = _container(channel, 120);
    await pumpEventQueue();
    container.read(settingsProvider.notifier).setLyricsAboveSeekBar(true);
    container.read(settingsProvider.notifier).setDisplayRefreshRate(120);
    await pumpEventQueue();
    expect(channel.sent, [120]);
  });

  test('display reports from Android update the state', () async {
    final channel = _FakeChannel();
    final container = _container(channel, 120);
    await pumpEventQueue();
    channel.push({
      'attached': true,
      'preferenceHz': 120,
      'activeModeId': 3,
      'activeModeHz': 120.0,
      'supportedRates': [60, 90, 120],
    });
    await pumpEventQueue();
    final state = container.read(displayRefreshProvider);
    expect(displayRefreshStatus(120, state), DisplayRefreshStatus.active);
    expect(channel.sent, [120]);
  });

  test(
    'a controller that attached after Dart started gets the saved choice once',
    () async {
      final channel = _FakeChannel();
      _container(channel, 120);
      await pumpEventQueue();
      expect(channel.sent, [120]);
      // An Activity added a fresh controller, which holds no preference.
      channel.push({'attached': true, 'preferenceHz': 0, 'activeModeHz': 60.0});
      channel.push({'attached': true, 'preferenceHz': 0, 'activeModeHz': 60.0});
      await pumpEventQueue();
      expect(channel.sent, [120, 120]);
      // Once it holds the preference, its pushes send nothing.
      channel.push({
        'attached': true,
        'preferenceHz': 120,
        'activeModeHz': 60.0,
      });
      await pumpEventQueue();
      expect(channel.sent, [120, 120]);
    },
  );

  test('a push without an Activity sends nothing', () async {
    final channel = _FakeChannel();
    _container(channel, 120);
    await pumpEventQueue();
    channel.push({'attached': false, 'preferenceHz': 0});
    await pumpEventQueue();
    expect(channel.sent, [120]);
  });

  test('disposing stops receiving pushes', () async {
    final channel = _FakeChannel();
    final container = _container(channel);
    await pumpEventQueue();
    expect(channel.onState, isNotNull);
    container.dispose();
    expect(channel.onState, isNull);
  });

  test('without a platform nothing is sent', () async {
    final container = ProviderContainer(
      overrides: [displayRefreshChannelProvider.overrideWithValue(null)],
    );
    addTearDown(container.dispose);
    expect(container.read(displayRefreshProvider).attached, isFalse);
  });
}
