import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/providers/performance/glass_poc_mode_provider.dart';
import 'package:sistrum/screens/settings/developer/glass_poc_page.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_runner.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_scene.dart';

final _shortPlan = GlassBenchmarkPlan(
  modes: [SistrumGlassMode.transparentBaseline, SistrumGlassMode.basicBlur],
  transition: Duration(milliseconds: 100),
  warmup: Duration(milliseconds: 200),
  measure: Duration(milliseconds: 500),
  modeTimeout: Duration(seconds: 3),
);

void main() {
  testWidgets(
    'the benchmark runs every mode, disables controls, restores the page and copies the full report',
    (tester) async {
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);
      // The page must restore this configuration after the run.
      container
          .read(glassPocModeProvider.notifier)
          .select(SistrumGlassMode.referenceGlass);
      container
          .read(glassPocSceneProvider.notifier)
          .select(SistrumGlassScene.fourSurfaces);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: GlassPocPage(benchmarkPlan: _shortPlan)),
        ),
      );

      final start = find.widgetWithText(ActionChip, 'Run Full Benchmark');
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pump();

      // While running, the mode and scene chips take no input.
      final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'New Full Glass'),
      );
      expect(chip.onSelected, isNull);
      expect(
        tester
            .widget<ActionChip>(
              find.widgetWithText(ActionChip, 'Run Full Benchmark'),
            )
            .onPressed,
        isNull,
        reason: 'no overlapping runs',
      );

      // Advance the fake clock until the report dialog opens.
      var opened = false;
      for (var i = 0; i < 200 && !opened; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        opened = find.text('Glass benchmark report').evaluate().isNotEmpty;
      }
      final statusText = tester
          .widget<Text>(find.byKey(const Key('benchmarkStatus')))
          .data;
      expect(
        opened,
        isTrue,
        reason: 'report dialog should open at the end; status: $statusText',
      );

      // The POC configuration was restored.
      expect(
        container.read(glassPocModeProvider),
        SistrumGlassMode.referenceGlass,
      );
      expect(
        container.read(glassPocSceneProvider),
        SistrumGlassScene.fourSurfaces,
      );

      // Copy Report copies the whole text, including every mode.
      final dialog = find.byType(AlertDialog);
      await tester.tap(
        find.descendant(of: dialog, matching: find.text('Copy Report')),
      );
      await tester.pump();
      expect(copied, isNotNull);
      expect(copied, startsWith('sistrum-glass-benchmark\nstatus=COMPLETE'));
      expect(copied, contains('-- Transparent Baseline'));
      expect(copied, contains('-- Basic Blur'));
      expect(copied, contains('No winner is declared'));
      expect(copied, contains('device_model=not accessible'));
      expect(copied, contains('scroll_speed_target=900'));

      await tester.tap(
        find.descendant(of: dialog, matching: find.text('Close')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        tester
            .widget<ActionChip>(
              find.widgetWithText(ActionChip, 'Run Full Benchmark'),
            )
            .onPressed,
        isNotNull,
        reason: 'a new run can start after the report',
      );
    },
  );
}
