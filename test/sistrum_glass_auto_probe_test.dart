import 'dart:convert';
import 'dart:ui' show FrameTiming;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/services/sistrum_glass_auto_probe.dart';
import 'package:sistrum/widgets/sistrum_glass_auto_probe_host.dart';

const _second = 1000000;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('sampler', () {
    test('skips the warm-up, then reports the p90 of a full window', () {
      final sampler = SistrumGlassAutoSampler();
      // Startup frames are ignored however slow they are.
      for (var i = 0; i < 100; i++) {
        expect(sampler.add(rasterMs: 80, vsyncMicros: i * 10000), isNull);
      }
      expect(sampler.frames, 0);
      double? p90;
      for (var i = 0; i < SistrumGlassAutoSampler.windowFrames; i++) {
        p90 = sampler.add(
          rasterMs: (i % 10 + 1).toDouble(),
          vsyncMicros: 4 * _second + i * 16667,
        );
        if (i < SistrumGlassAutoSampler.windowFrames - 1) expect(p90, isNull);
      }
      expect(p90, 9);
    });

    test('steps down only above the threshold, never below Level 1 lite', () {
      const full = SistrumGlassAutoStep.full;
      const lite = SistrumGlassAutoStep.lite;
      const frosted = SistrumGlassAutoStep.liteFrosted;
      expect(SistrumGlassAutoSampler.stepDown(full, 14), isNull);
      expect(SistrumGlassAutoSampler.stepDown(full, 14.1), lite);
      expect(SistrumGlassAutoSampler.stepDown(lite, 13), isNull);
      expect(SistrumGlassAutoSampler.stepDown(lite, 30), frosted);
      expect(SistrumGlassAutoSampler.stepDown(frosted, 99), isNull);
    });
  });

  group('persistence', () {
    test('a result is kept for its build only', () async {
      const result = SistrumGlassAutoResult(
        build: '5.1.1+168',
        step: SistrumGlassAutoStep.lite,
        done: true,
        p90: 15.5,
      );
      await saveGlassAutoResult(result);
      final prefs = await SharedPreferences.getInstance();
      expect(loadGlassAutoResult(prefs, build: '5.1.1+168'), result);
      // An app update measures again.
      expect(loadGlassAutoResult(prefs, build: '5.1.2+169'), isNull);
      await saveGlassAutoResult(null);
      expect(prefs.containsKey(kGlassAutoProbeKey), isFalse);
    });

    test('unreadable results are ignored', () async {
      for (final raw in ['{not json', '{"build":"b","step":"huge"}', '[]']) {
        SharedPreferences.setMockInitialValues({kGlassAutoProbeKey: raw});
        final prefs = await SharedPreferences.getInstance();
        expect(loadGlassAutoResult(prefs, build: 'b'), isNull, reason: raw);
      }
    });
  });

  ProviderContainer container({
    String quality = 'auto',
    SistrumGlassAutoResult? result,
    bool lowEnd = false,
    bool liquidCapable = true,
  }) {
    final container = ProviderContainer(
      overrides: [
        initialSettingsProvider.overrideWithValue(
          AppSettings(glassQuality: quality, glassClarityLevel: 4),
        ),
        initialGlassAutoResultProvider.overrideWithValue(result),
        lowEndDeviceProvider.overrideWithValue(lowEnd),
        deviceSupportsLiquidGlassProvider.overrideWithValue(liquidCapable),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  SistrumGlassAutoResult measured(SistrumGlassAutoStep step) =>
      SistrumGlassAutoResult(build: 'b', step: step, done: true, p90: 20);

  test('a measured step lowers Auto, and only Auto', () {
    final cases = [
      // (quality, result, lowEnd, liquidCapable) -> (level, clarity, status)
      ('auto', null, false, true, SistrumGlassLevel.liquid, 4, 'measuring'),
      (
        'auto',
        SistrumGlassAutoStep.full,
        false,
        true,
        SistrumGlassLevel.liquid,
        4,
        'measured',
      ),
      (
        'auto',
        SistrumGlassAutoStep.lite,
        false,
        true,
        SistrumGlassLevel.lite,
        4,
        'measured',
      ),
      (
        'auto',
        SistrumGlassAutoStep.liteFrosted,
        false,
        true,
        SistrumGlassLevel.lite,
        1,
        'measured',
      ),
      // A lite-class device starts measuring at lite.
      ('auto', null, false, false, SistrumGlassLevel.lite, 4, 'measuring'),
      // Low-end devices keep glass off and never measure.
      (
        'auto',
        SistrumGlassAutoStep.liteFrosted,
        true,
        true,
        SistrumGlassLevel.flat,
        4,
        'device',
      ),
      // An explicit choice ignores the measurement.
      (
        'full',
        SistrumGlassAutoStep.liteFrosted,
        false,
        true,
        SistrumGlassLevel.liquid,
        4,
        'device',
      ),
      (
        'lite',
        SistrumGlassAutoStep.liteFrosted,
        false,
        true,
        SistrumGlassLevel.lite,
        4,
        'device',
      ),
    ];
    for (final (quality, step, lowEnd, liquid, level, clarity, status)
        in cases) {
      final c = container(
        quality: quality,
        result: step == null ? null : measured(step),
        lowEnd: lowEnd,
        liquidCapable: liquid,
      );
      final reason = '$quality $step lowEnd:$lowEnd liquid:$liquid';
      expect(c.read(sistrumGlassLevelProvider), level, reason: reason);
      expect(c.read(sistrumGlassClarityLevelProvider), clarity, reason: reason);
      expect(
        c.read(sistrumGlassAutoStatusProvider(false)).name,
        status,
        reason: reason,
      );
    }
    // High contrast blocks Auto's glass, so nothing is measured.
    expect(
      container().read(sistrumGlassAutoStatusProvider(true)),
      SistrumGlassAutoStatus.device,
    );
  });

  group('host', () {
    var clock = 0;
    setUp(() => clock = 0);

    /// Reports [count] frames of [rasterMs] at 60 Hz, as the engine would.
    void report(WidgetTester tester, int count, double rasterMs) {
      final timings = <FrameTiming>[];
      for (var i = 0; i < count; i++) {
        clock += 16667;
        timings.add(
          FrameTiming(
            vsyncStart: clock,
            buildStart: clock,
            buildFinish: clock + 3000,
            rasterStart: clock + 3000,
            rasterFinish: clock + 3000 + (rasterMs * 1000).round(),
            rasterFinishWallTime: clock + 3000 + (rasterMs * 1000).round(),
          ),
        );
      }
      tester.binding.platformDispatcher.onReportTimings!(timings);
    }

    /// Exactly the sampler's warm-up: 3 s of slow startup frames.
    void warmUp(WidgetTester tester) => report(tester, 180, 40);

    Future<ProviderContainer> pumpHost(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialSettingsProvider.overrideWithValue(const AppSettings()),
          ],
          child: const SistrumGlassAutoProbeHost(child: SizedBox()),
        ),
      );
      await tester.pump();
      return ProviderScope.containerOf(tester.element(find.byType(SizedBox)));
    }

    Future<Map<String, dynamic>?> saved() async {
      final raw = (await SharedPreferences.getInstance()).getString(
        kGlassAutoProbeKey,
      );
      return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
    }

    testWidgets('a slow device steps full -> lite -> Level 1 and saves it', (
      tester,
    ) async {
      final c = await pumpHost(tester);
      expect(SistrumGlassAutoProbeHost.debugActiveSamplers, 1);
      expect(c.read(sistrumGlassLevelProvider), SistrumGlassLevel.liquid);
      // Warm-up (3 s) and then a full window at 22 ms.
      warmUp(tester);
      report(tester, SistrumGlassAutoSampler.windowFrames, 22);
      await tester.pump();
      expect(c.read(sistrumGlassLevelProvider), SistrumGlassLevel.lite);
      expect(c.read(sistrumGlassClarityLevelProvider), 3);
      expect(
        c.read(sistrumGlassAutoStatusProvider(false)),
        SistrumGlassAutoStatus.measuring,
      );
      expect((await saved())!['step'], 'lite');
      expect((await saved())!['done'], false);

      // Lite is measured again after its own warm-up.
      warmUp(tester);
      report(tester, SistrumGlassAutoSampler.windowFrames, 16);
      await tester.pump();
      expect(c.read(sistrumGlassLevelProvider), SistrumGlassLevel.lite);
      expect(c.read(sistrumGlassClarityLevelProvider), 1);
      expect(
        c.read(sistrumGlassAutoStatusProvider(false)),
        SistrumGlassAutoStatus.measured,
      );
      final result = await saved();
      expect(result!['step'], 'liteFrosted');
      expect(result['done'], true);
      expect(result['build'], sistrumGlassAutoBuild());
      // The stored clarity choice is untouched.
      expect(c.read(settingsProvider).glassClarityLevel, 3);

      // Measured: nothing samples any more.
      expect(SistrumGlassAutoProbeHost.debugActiveSamplers, 0);
      report(tester, 400, 60);
      await tester.pump();
      expect((await saved())!['step'], 'liteFrosted');
    });

    testWidgets('a fast device keeps full glass', (tester) async {
      final c = await pumpHost(tester);
      warmUp(tester);
      report(tester, SistrumGlassAutoSampler.windowFrames, 9);
      await tester.pump();
      expect(c.read(sistrumGlassLevelProvider), SistrumGlassLevel.liquid);
      expect(
        c.read(sistrumGlassAutoStatusProvider(false)),
        SistrumGlassAutoStatus.measured,
      );
      expect((await saved())!['step'], 'full');

      // Measuring again clears it.
      c.read(sistrumGlassAutoResultProvider.notifier).clear();
      await tester.pump();
      expect(await saved(), isNull);
      expect(
        c.read(sistrumGlassAutoStatusProvider(false)),
        SistrumGlassAutoStatus.measuring,
      );
    });

    testWidgets('an explicit quality is never measured', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialSettingsProvider.overrideWithValue(
              const AppSettings(glassQuality: 'full'),
            ),
          ],
          child: const SistrumGlassAutoProbeHost(child: SizedBox()),
        ),
      );
      report(tester, 1, 40);
      await tester.pump();
      expect(SistrumGlassAutoProbeHost.debugActiveSamplers, 0);
    });
  });
}
