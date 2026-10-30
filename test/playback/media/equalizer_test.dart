import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/core/models/equalizer_settings.dart';
import 'package:sistrum/providers/equalizer_provider.dart';
import 'package:sistrum/services/playback/audio/playback_equalizer.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    playbackEqualizer.value = const EqualizerSettings();
    playbackEqualizerError.value = null;
  });

  {
    const format = 'sistrum-equalizer';
    test('preset imports use the Sistrum wire format', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(equalizerProvider.notifier);
      notifier.importPreset(
        jsonEncode({
          'format': format,
          'version': 1,
          ...const EqualizerPreset(
            'Legacy headphones',
            EqualizerSettings(preamp: -6, bass: 3),
          ).toJson(),
        }),
      );
      final state = container.read(equalizerProvider);
      expect(state.settings.preamp, -6);
      expect(state.settings.bass, 3);
      expect(state.presets.single.name, 'Legacy headphones');
      final exported = jsonDecode(notifier.exportPreset('Current')) as Map;
      expect(exported['format'], 'sistrum-equalizer');
      expect(exported['version'], 1);
      expect(
        () => notifier.importPreset(
          jsonEncode({...exported, 'format': 'foreign-equalizer'}),
        ),
        throwsFormatException,
      );
    });
  }

  test('band resampling preserves flat curves and center gains', () {
    for (final count in EqualizerSettings.bandCounts) {
      final settings = const EqualizerSettings().withBandCount(count);
      expect(settings.gains, everyElement(0));
      expect(settings.frequencies.length, count);
      final raised = settings.copyWith(gains: List.filled(count, 6));
      for (final hz in raised.frequencies) {
        expect(raised.gainAt(hz), closeTo(6, 1e-9));
      }
      expect(raised.withBandCount(31).gains, everyElement(closeTo(6, 1e-9)));
    }
    expect(const EqualizerSettings().withBandCount(31).frequencies.take(3), [
      20,
      25,
      31.5,
    ]);
    expect(
      () => const EqualizerSettings().withBandCount(32),
      throwsFormatException,
    );
  });

  test('tone controls and automatic headroom reach the native payload', () {
    const settings = EqualizerSettings(
      enabled: true,
      bass: 6,
      treble: -3,
      preamp: -2,
    );
    final payload = settings.toNative();
    expect(settings.effectiveGains.first, greaterThan(5));
    expect(settings.effectiveGains.last, lessThan(-2));
    expect(payload['inputGain'], lessThan(-7));
    expect(payload['gains'], settings.effectiveGains);
    expect(settings.copyWith(autoHeadroom: false).inputGain, -2);
  });

  test('presets change the sound but keep output safety choices', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(equalizerProvider.notifier);
    notifier.update(
      const EqualizerSettings(
        enabled: true,
        balance: 0.25,
        autoHeadroom: false,
        limiter: false,
        compressor: true,
        ratio: 6,
      ),
    );
    final bassBoost = EqualizerPreset.builtIn.firstWhere(
      (preset) => preset.name == 'Bass boost',
    );
    notifier.applyPreset(bassBoost);
    final settings = container.read(equalizerProvider).settings;
    expect(settings.gains, bassBoost.settings.gains);
    expect(settings.enabled, isTrue);
    expect(settings.balance, 0.25);
    expect(settings.autoHeadroom, isFalse);
    expect(settings.limiter, isFalse);
    expect(settings.compressor, isTrue);
    expect(settings.ratio, 6);
    expect(settings.inputGain, 0);
  });

  test(
    'malformed and nonfinite imports cannot create unsafe native settings',
    () {
      final json = const EqualizerSettings().toJson();
      expect(
        () => EqualizerSettings.fromJson({
          ...json,
          'gains': [1, 2],
        }),
        throwsFormatException,
      );
      expect(
        () => EqualizerSettings.fromJson({
          ...json,
          'gains': List.filled(10, double.nan),
        }),
        throwsFormatException,
      );
      final bounded = EqualizerSettings.fromJson({
        ...json,
        'gains': List.filled(10, 100),
        'preamp': 1000,
        'balance': -100,
        'ratio': double.infinity,
      });
      expect(bounded.gains, everyElement(15));
      expect(bounded.preamp, 12);
      expect(bounded.balance, -1);
      expect(bounded.ratio, 3);
    },
  );

  testWidgets('presets survive fast edits during startup and reload', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      EqualizerController.storageKey: jsonEncode({
        'settings': const EqualizerSettings(preamp: -4).toJson(),
        'presets': [
          const EqualizerPreset(
            'Headphones',
            EqualizerSettings(bass: 3),
          ).toJson(),
        ],
      }),
    });
    final container = ProviderContainer();
    container.read(equalizerProvider);
    container
        .read(equalizerProvider.notifier)
        .update(const EqualizerSettings(enabled: true, treble: 2));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump(const Duration(milliseconds: 500));
    expect(container.read(equalizerProvider).settings.treble, 2);
    expect(container.read(equalizerProvider).presets.single.name, 'Headphones');
    final notifier = container.read(equalizerProvider.notifier);
    notifier.savePreset('Desk');
    notifier.update(const EqualizerSettings(enabled: true, preamp: -8));
    final export = notifier.exportPreset('Portable');
    notifier.importPreset(export);
    expect(container.read(equalizerProvider).presets.map((v) => v.name), [
      'Headphones',
      'Desk',
      'Portable',
    ]);
    expect(container.read(equalizerProvider).settings.enabled, isTrue);
    expect(() => notifier.importPreset('{}'), throwsFormatException);
    expect(() => notifier.importPreset('x' * 65537), throwsFormatException);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    container.dispose();
    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    restored.read(equalizerProvider);
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(restored.read(equalizerProvider).settings.preamp, -8);
    expect(restored.read(equalizerProvider).presets.length, 3);
  });
}
