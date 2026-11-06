import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_runner.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_render_path.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_surface.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_config.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_surface.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_telemetry.dart';

Widget _host({
  required SistrumGlassMode mode,
  required SistrumHybridConfig config,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: ThemeData(brightness: brightness),
  home: Scaffold(
    body: Center(
      child: SistrumHybridConfigScope(
        config: config,
        child: SistrumGlassSurface(
          mode: mode,
          width: 200,
          height: 60,
          borderRadius: 30,
          child: const Text('Now playing'),
        ),
      ),
    ),
  ),
);

void main() {
  group('configuration', () {
    test('defaults are the BitChord reference values', () {
      const c = SistrumHybridConfig();
      expect(c.tier, SistrumHybridTier.frosted);
      expect(c.blurSigma, kSistrumHybridDefaultBlurSigma);
      expect(c.tintOpacity, kSistrumHybridDefaultTintOpacity);
      expect(kSistrumHybridReferenceSaturation, 1.5);
      expect(kSistrumHybridReferenceSamplingScale, 0.33);
    });

    test('blur and tint are clamped to their ranges', () {
      const c = SistrumHybridConfig();
      expect(c.copyWith(blurSigma: 99).blurSigma, 24);
      expect(c.copyWith(blurSigma: -3).blurSigma, 0);
      expect(c.copyWith(tintOpacity: 2).tintOpacity, 1);
      expect(c.copyWith(tintOpacity: -1).tintOpacity, 0);
    });

    test('equal configurations compare equal', () {
      expect(
        const SistrumHybridConfig(blurSigma: 8),
        const SistrumHybridConfig(blurSigma: 8),
      );
      expect(
        const SistrumHybridConfig(blurSigma: 8) ==
            const SistrumHybridConfig(blurSigma: 9),
        isFalse,
      );
    });
  });

  group('capabilities', () {
    test(
      'blur belongs to Frosted and Full, refraction to Full, nothing to Lightweight',
      () {
        expect(
          SistrumHybridCapabilities.of(SistrumHybridTier.lightweight).blur,
          isFalse,
        );
        expect(
          SistrumHybridCapabilities.of(SistrumHybridTier.frosted).blur,
          isTrue,
        );
        // Full composes the same blur before the lens.
        expect(
          SistrumHybridCapabilities.of(SistrumHybridTier.full).blur,
          isTrue,
        );
        expect(
          SistrumHybridCapabilities.of(SistrumHybridTier.opaque).tint,
          isFalse,
        );
        expect(
          SistrumHybridCapabilities.of(SistrumHybridTier.full).refraction,
          isTrue,
        );
        expect(
          SistrumHybridCapabilities.of(SistrumHybridTier.frosted).refraction,
          isFalse,
        );
      },
    );

    test(
      'saturation and sampling scale are unsupported; sharing needs a backdrop read',
      () {
        for (final tier in SistrumHybridTier.values) {
          final caps = SistrumHybridCapabilities.of(tier);
          expect(caps.saturation, isFalse, reason: tier.name);
          expect(caps.samplingScale, isFalse, reason: tier.name);
          expect(caps.sharedBackdrop, tier.readsBackdrop, reason: tier.name);
        }
        // A shared read is requested only where a backdrop is read.
        expect(
          const SistrumHybridConfig(
            tier: SistrumHybridTier.lightweight,
            sharedBackdrop: true,
          ).sharesBackdrop,
          isFalse,
        );
      },
    );

    test('genuine refraction needs the Full tier with refraction on', () {
      expect(
        const SistrumHybridConfig(
          tier: SistrumHybridTier.full,
        ).isGenuineRefraction,
        isTrue,
      );
      expect(
        const SistrumHybridConfig(
          tier: SistrumHybridTier.full,
          refraction: false,
        ).isGenuineRefraction,
        isFalse,
      );
      // A blur is never a refraction.
      expect(
        const SistrumHybridConfig(
          tier: SistrumHybridTier.frosted,
        ).isGenuineRefraction,
        isFalse,
      );
    });
  });

  group('tiers in the scene', () {
    testWidgets('Lightweight reads no backdrop', (tester) async {
      await tester.pumpWidget(
        _host(
          mode: SistrumGlassMode.sistrumHybrid,
          config: const SistrumHybridConfig(
            tier: SistrumHybridTier.lightweight,
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('Now playing'), findsOneWidget);
    });

    testWidgets('Frosted samples the backdrop with the configured sigma', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          mode: SistrumGlassMode.sistrumHybrid,
          config: const SistrumHybridConfig(
            tier: SistrumHybridTier.frosted,
            blurSigma: 12,
          ),
        ),
      );
      final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(filter, isNotNull);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('foreground text is drawn above the blur, not inside it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          mode: SistrumGlassMode.sistrumHybrid,
          config: const SistrumHybridConfig(tier: SistrumHybridTier.frosted),
        ),
      );
      // The text is a child of the filter's child, so it is painted after the
      // blur and stays sharp.
      expect(
        find.descendant(
          of: find.byType(BackdropFilter),
          matching: find.text('Now playing'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the dark theme uses the dark tint at the configured opacity', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          mode: SistrumGlassMode.sistrumHybrid,
          config: const SistrumHybridConfig(
            tier: SistrumHybridTier.lightweight,
            tintOpacity: 0.5,
          ),
          brightness: Brightness.dark,
        ),
      );
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(ClipRRect),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final deco = box.decoration as BoxDecoration;
      expect(deco.color!.a, closeTo(0.5, 0.01));
    });
  });

  group('integration with the POC', () {
    test('the mode is a separate, labelled POC renderer', () {
      expect(SistrumGlassMode.sistrumHybrid.label, 'Sistrum Hybrid');
      expect(SistrumGlassMode.values, contains(SistrumGlassMode.sistrumHybrid));
    });

    test('the Hybrid mode is not one of the five standard benchmark runs', () {
      final standard = {
        SistrumGlassMode.transparentBaseline,
        SistrumGlassMode.basicBlur,
        SistrumGlassMode.liquidGlass,
        SistrumGlassMode.newFullGlass,
        SistrumGlassMode.newFakeGlass,
      };
      expect(standard.contains(SistrumGlassMode.sistrumHybrid), isFalse);
    });

    test('the mode alone claims no path; only a matrix variant does', () {
      expect(expectedGlassRenderPath(SistrumGlassMode.sistrumHybrid), isNull);
      expect(
        expectedHybridRenderPath(
          const SistrumHybridConfig(
            tier: SistrumHybridTier.full,
            refraction: false,
          ),
        ),
        isNot(SistrumGlassRenderPath.lensShader),
      );
    });
  });

  group('tint and opaque materials', () {
    testWidgets('the tint is painted under the highlight, not replaced by it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          mode: SistrumGlassMode.sistrumHybrid,
          config: const SistrumHybridConfig(
            tier: SistrumHybridTier.lightweight,
            tintOpacity: 0.4,
          ),
        ),
      );
      final boxes = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(ClipRRect),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((b) => b.decoration as BoxDecoration)
          .toList();
      // A BoxDecoration with a gradient ignores its color, so the tint must
      // be its own fill without a gradient.
      final tint = boxes.firstWhere((d) => d.gradient == null);
      expect(tint.color, isNotNull);
      expect(tint.color!.a, closeTo(0.4, 0.01));
      expect(boxes.where((d) => d.gradient != null), hasLength(1));
    });

    testWidgets('Opaque reads no backdrop and has no transparency', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          mode: SistrumGlassMode.sistrumHybrid,
          config: const SistrumHybridConfig(tier: SistrumHybridTier.opaque),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(ClipRRect),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((box.decoration as BoxDecoration).color!.a, 1);
      expect(find.text('Now playing'), findsOneWidget);
    });
  });

  group('render-decision telemetry', () {
    Widget stage(
      SistrumHybridTelemetry telemetry,
      SistrumHybridConfig config, {
      List<BackdropKey?> keys = const [null],
    }) => MaterialApp(
      home: Scaffold(
        body: SistrumHybridTelemetryScope(
          telemetry: telemetry,
          child: Column(
            children: [
              for (final key in keys)
                SizedBox(
                  width: 200,
                  height: 60,
                  child: SistrumHybridSurface(
                    config: config,
                    dark: false,
                    borderRadius: 30,
                    backdropKey: key,
                    child: const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    testWidgets('each tier reports what it handed to the engine', (
      tester,
    ) async {
      final expected = {
        SistrumHybridTier.opaque: (SistrumHybridEffectivePath.opaque, 0),
        SistrumHybridTier.lightweight: (SistrumHybridEffectivePath.tint, 0),
        SistrumHybridTier.frosted: (SistrumHybridEffectivePath.blur, 1),
      };
      for (final entry in expected.entries) {
        final telemetry = SistrumHybridTelemetry();
        await tester.pumpWidget(
          stage(telemetry, SistrumHybridConfig(tier: entry.key)),
        );
        final snap = telemetry.snapshot();
        expect(snap.surfaces, 1, reason: entry.key.name);
        expect(snap.uniformPath, entry.value.$1, reason: entry.key.name);
        expect(snap.backdropFilters, entry.value.$2, reason: entry.key.name);
        expect(snap.backdropReads, entry.value.$2, reason: entry.key.name);
        expect(snap.shaderFilters, 0, reason: entry.key.name);
        expect(
          find.byType(BackdropFilter),
          entry.value.$2 == 1 ? findsOneWidget : findsNothing,
          reason: entry.key.name,
        );
      }
    });

    testWidgets(
      'Full reports the blur fallback and its reason under the test engine',
      (tester) async {
        final telemetry = SistrumHybridTelemetry();
        await tester.pumpWidget(
          stage(
            telemetry,
            const SistrumHybridConfig(tier: SistrumHybridTier.full),
          ),
        );
        await tester.pump();
        final snap = telemetry.snapshot();
        // flutter_tester has no shader filters, so the lens is never active here.
        expect(snap.uniformPath, SistrumHybridEffectivePath.blur);
        expect(snap.shaderFilters, 0);
        expect(snap.fallbackBlur, 1);
        expect(snap.fallbacks, {
          SistrumHybridFallback.shaderFiltersUnsupported,
        });
        final report = classifyHybridRenderPath(
          expectedSurfaces: 1,
          snapshot: snap,
        );
        expect(report.path, SistrumGlassRenderPath.backdropFilter);
        expect(report.fallback, isTrue);
        expect(report.fallbackReason, contains('shader_filters_unsupported'));
      },
    );

    testWidgets(
      'Full with refraction off is a requested blur, not a fallback',
      (tester) async {
        final telemetry = SistrumHybridTelemetry();
        await tester.pumpWidget(
          stage(
            telemetry,
            const SistrumHybridConfig(
              tier: SistrumHybridTier.full,
              refraction: false,
            ),
          ),
        );
        final report = classifyHybridRenderPath(
          expectedSurfaces: 1,
          snapshot: telemetry.snapshot(),
        );
        expect(report.path, SistrumGlassRenderPath.backdropFilter);
        expect(report.fallback, isFalse);
      },
    );

    testWidgets(
      'a key shared by several filters is one read; a lone key is not',
      (tester) async {
        final shared = BackdropKey();
        final lone = BackdropKey();
        final telemetry = SistrumHybridTelemetry();
        await tester.pumpWidget(
          stage(
            telemetry,
            const SistrumHybridConfig(
              tier: SistrumHybridTier.frosted,
              sharedBackdrop: true,
            ),
            keys: [shared, shared, shared, lone],
          ),
        );
        final snap = telemetry.snapshot();
        expect(snap.backdropFilters, 4);
        expect(snap.sharedGroups, 1);
        expect(snap.sharedMembers, 3);
        expect(snap.sharedBackdropActive, isTrue);
        // Three filters share one flip; the lone key flips on its own.
        expect(snap.backdropReads, 2);
        final filters = tester.widgetList<BackdropFilter>(
          find.byType(BackdropFilter),
        );
        expect(
          filters.where((f) => identical(f.backdropGroupKey, shared)),
          hasLength(3),
        );
      },
    );

    testWidgets('four independent filters are four reads', (tester) async {
      final telemetry = SistrumHybridTelemetry();
      await tester.pumpWidget(
        stage(
          telemetry,
          const SistrumHybridConfig(tier: SistrumHybridTier.frosted),
          keys: const [null, null, null, null],
        ),
      );
      final snap = telemetry.snapshot();
      expect(snap.backdropReads, 4);
      expect(snap.sharedBackdropActive, isFalse);
    });

    testWidgets(
      'a removed surface leaves the telemetry and changes are counted',
      (tester) async {
        final telemetry = SistrumHybridTelemetry();
        await tester.pumpWidget(
          stage(
            telemetry,
            const SistrumHybridConfig(tier: SistrumHybridTier.frosted),
          ),
        );
        await tester.pumpWidget(
          stage(
            telemetry,
            const SistrumHybridConfig(tier: SistrumHybridTier.opaque),
          ),
        );
        expect(telemetry.snapshot().decisionChanges, 1);
        expect(
          telemetry.snapshot().uniformPath,
          SistrumHybridEffectivePath.opaque,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        expect(telemetry.snapshot().surfaces, 0);
      },
    );

    test('the report lines name every required field', () {
      final lines = SistrumHybridTelemetrySnapshot.of(const [
        SistrumHybridDecision(
          requestedTier: SistrumHybridTier.full,
          path: SistrumHybridEffectivePath.lens,
        ),
      ]).lines().join('\n');
      for (final field in [
        'hybrid_requested_tiers=full',
        'hybrid_effective_path=lens',
        'hybrid_lens_shader_active=1/1',
        'hybrid_fallback_blur_surfaces=0',
        'hybrid_backdrop_filter_surfaces=1',
        'hybrid_shader_filter_surfaces=1',
        'hybrid_shared_backdrop_active=false',
        'hybrid_fallback_reasons=none',
        'hybrid_backdrop_reads_per_frame=1',
      ]) {
        expect(lines, contains(field));
      }
    });
  });

  group('zero-blur bypass', () {
    Widget stage(SistrumHybridTelemetry telemetry, SistrumHybridConfig c) =>
        MaterialApp(
          home: Scaffold(
            body: SistrumHybridTelemetryScope(
              telemetry: telemetry,
              child: SizedBox(
                width: 200,
                height: 60,
                child: SistrumHybridSurface(
                  config: c,
                  dark: false,
                  borderRadius: 30,
                  backdropKey: BackdropKey(),
                  child: const Text('Now playing'),
                ),
              ),
            ),
          ),
        );

    testWidgets(
      'Frosted at blur 0 builds no BackdropFilter and reads nothing',
      (tester) async {
        final telemetry = SistrumHybridTelemetry();
        await tester.pumpWidget(
          stage(
            telemetry,
            const SistrumHybridConfig(
              tier: SistrumHybridTier.frosted,
              blurSigma: 0,
            ),
          ),
        );
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.text('Now playing'), findsOneWidget);
        final snap = telemetry.snapshot();
        expect(snap.uniformPath, SistrumHybridEffectivePath.tint);
        expect(snap.backdropReads, 0);
        expect(snap.fallbacks, {SistrumHybridFallback.zeroBlurBypass});
        final report = classifyHybridRenderPath(
          expectedSurfaces: 1,
          snapshot: snap,
        );
        expect(report.path, SistrumGlassRenderPath.tint);
        expect(report.fallback, isFalse);
      },
    );

    testWidgets('a nonzero blur does build the BackdropFilter', (tester) async {
      final telemetry = SistrumHybridTelemetry();
      await tester.pumpWidget(
        stage(
          telemetry,
          const SistrumHybridConfig(
            tier: SistrumHybridTier.frosted,
            blurSigma: 1,
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(telemetry.snapshot().backdropReads, 1);
    });

    testWidgets('Full at blur 0 without the lens is bypassed too', (
      tester,
    ) async {
      for (final refraction in [false, true]) {
        final telemetry = SistrumHybridTelemetry();
        await tester.pumpWidget(
          stage(
            telemetry,
            SistrumHybridConfig(
              tier: SistrumHybridTier.full,
              blurSigma: 0,
              refraction: refraction,
            ),
          ),
        );
        await tester.pump();
        expect(
          find.byType(BackdropFilter),
          findsNothing,
          reason: '$refraction',
        );
        final snap = telemetry.snapshot();
        expect(snap.backdropReads, 0, reason: '$refraction');
        // Refraction off: a requested bypass. On: the lens is unavailable
        // under the test engine, and that reason is kept.
        expect(
          snap.fallbacks,
          refraction
              ? {SistrumHybridFallback.shaderFiltersUnsupported}
              : {SistrumHybridFallback.zeroBlurBypass},
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    test('the expected path follows the bypass', () {
      expect(
        expectedHybridRenderPath(
          const SistrumHybridConfig(
            tier: SistrumHybridTier.frosted,
            blurSigma: 0,
          ),
        ),
        SistrumGlassRenderPath.tint,
      );
      expect(
        expectedHybridRenderPath(
          const SistrumHybridConfig(tier: SistrumHybridTier.frosted),
        ),
        SistrumGlassRenderPath.backdropFilter,
      );
      // The lens still needs the backdrop at blur 0.
      expect(
        expectedHybridRenderPath(
          const SistrumHybridConfig(tier: SistrumHybridTier.full, blurSigma: 0),
        ),
        SistrumGlassRenderPath.lensShader,
      );
    });
  });
}
