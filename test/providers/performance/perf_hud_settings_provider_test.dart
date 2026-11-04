import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/providers/performance/perf_hud_settings_provider.dart';

Future<PerfHudSettings> _loaded(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(initial);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(perfHudSettingsProvider);
  // Let the asynchronous load finish.
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return container.read(perfHudSettingsProvider);
}

void main() {
  test('defaults keep the HUD off and Developer Options locked', () async {
    final settings = await _loaded({});
    expect(settings.enabled, isFalse);
    expect(settings.developerUnlocked, isFalse);
    expect(settings.compact, isTrue);
    expect(settings.position, isNull);
    expect(settings.opacity, closeTo(0.88, 0.001));
  });

  test('saved state is restored on load', () async {
    final settings = await _loaded({
      'perf_hud_enabled': true,
      'perf_hud_dx': 12.5,
      'perf_hud_dy': 40.0,
      'perf_hud_compact': false,
      'perf_hud_opacity': 0.6,
      'developer_options_unlocked': true,
    });
    expect(settings.enabled, isTrue);
    expect(settings.position, (dx: 12.5, dy: 40.0));
    expect(settings.compact, isFalse);
    expect(settings.opacity, closeTo(0.6, 0.001));
    expect(settings.developerUnlocked, isTrue);
  });

  test('opacity is clamped to a readable range', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(perfHudSettingsProvider.notifier);
    notifier.setOpacity(0.05);
    expect(container.read(perfHudSettingsProvider).opacity, 0.4);
    notifier.setOpacity(3);
    expect(container.read(perfHudSettingsProvider).opacity, 1.0);
  });

  test('changes persist and survive a fresh load', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(perfHudSettingsProvider.notifier);
    notifier
      ..setEnabled(true)
      ..setPosition(30, 90)
      ..setCompact(false)
      ..unlockDeveloperOptions();
    await Future<void>.delayed(Duration.zero);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('perf_hud_enabled'), isTrue);
    expect(prefs.getDouble('perf_hud_dx'), 30);
    expect(prefs.getDouble('perf_hud_dy'), 90);
    expect(prefs.getBool('perf_hud_compact'), isFalse);
    expect(prefs.getBool('developer_options_unlocked'), isTrue);
  });

  test('unlocking is one-way and idempotent', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(perfHudSettingsProvider.notifier);
    notifier.unlockDeveloperOptions();
    notifier.unlockDeveloperOptions();
    expect(container.read(perfHudSettingsProvider).developerUnlocked, isTrue);
  });
}
