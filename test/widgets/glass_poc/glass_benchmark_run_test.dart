import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_run.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_runner.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';

void main() {
  test('the standard protocol keeps five modes, four surfaces, one repeat', () {
    final plan = GlassBenchmarkPlan();
    expect(plan.runs, hasLength(5));
    expect(plan.diagnostic, isFalse);
    for (final run in plan.runs) {
      expect(run.surfaces, 4);
      expect(run.repeat, 1);
    }
  });

  test('the diagnostic configurations cover the first investigation', () {
    final configs = glassDiagnosticConfigurations();
    expect(configs.map((c) => c.configKey), [
      'transparentBaseline-s4',
      'newFullGlass-s1',
      'newFullGlass-s2',
      'newFullGlass-s4',
      'liquidGlass-s4',
      'newFakeGlass-s4',
    ]);
    expect(
      glassDiagnosticConfigurations(includeBasicBlur: true).last.mode,
      SistrumGlassMode.basicBlur,
    );
  });

  test('each round runs every configuration exactly once', () {
    final configs = glassDiagnosticConfigurations();
    final order = glassDiagnosticRunOrder(configurations: configs);
    expect(order, hasLength(configs.length * 3));
    for (var round = 1; round <= 3; round++) {
      final keys = [
        for (final r in order)
          if (r.repeat == round) r.configKey,
      ];
      expect(keys.toSet(), hasLength(configs.length));
      expect(keys, hasLength(configs.length));
    }
  });

  test('positions change between rounds, so no configuration is fixed', () {
    final configs = glassDiagnosticConfigurations();
    final order = glassDiagnosticRunOrder(configurations: configs);
    for (final c in configs) {
      final positions = <int>{};
      for (var round = 1; round <= 3; round++) {
        final roundRuns = [
          for (final r in order)
            if (r.repeat == round) r,
        ];
        positions.add(roundRuns.indexWhere((r) => r.configKey == c.configKey));
      }
      expect(
        positions.length,
        greaterThan(1),
        reason: '${c.configKey} stayed in one position in every round',
      );
    }
  });

  test('the order is deterministic', () {
    final configs = glassDiagnosticConfigurations();
    final a = glassDiagnosticRunOrder(configurations: configs);
    final b = glassDiagnosticRunOrder(configurations: configs);
    expect(
      [for (final r in a) '${r.configKey}#${r.repeat}'],
      [for (final r in b) '${r.configKey}#${r.repeat}'],
    );
  });

  test('the diagnostic plan inherits the timing of the page plan', () {
    final timing = GlassBenchmarkPlan(
      transition: const Duration(milliseconds: 100),
      warmup: const Duration(milliseconds: 200),
      measure: const Duration(seconds: 3),
      modeTimeout: const Duration(seconds: 4),
    );
    final plan = GlassBenchmarkPlan.diagnostic(timing: timing);
    expect(plan.diagnostic, isTrue);
    expect(plan.runs, hasLength(18));
    expect(plan.warmup, timing.warmup);
    expect(plan.measure, timing.measure);
    expect(plan.transition, timing.transition);
    expect(plan.modeTimeout, timing.modeTimeout);
  });

  test('the layer-count scaling values are 1, 2 and 4', () {
    expect(kGlassLayerScalingSurfaces, [1, 2, 4]);
  });
}
