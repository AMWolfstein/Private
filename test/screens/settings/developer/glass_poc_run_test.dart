import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/providers/performance/glass_poc_mode_provider.dart';
import 'package:sistrum/screens/settings/developer/glass_poc_page.dart';
import 'package:sistrum/services/performance/perf_frame_monitor.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_auto_scroll.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: GlassPocPage()),
    ),
  );
  return container;
}

Future<void> _tap(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(ChoiceChip, label);
  final action = find.widgetWithText(ActionChip, label);
  final target = chip.evaluate().isNotEmpty ? chip : action;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
}

ScrollPosition _list(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

void _addFrame(PerfFrameMonitor monitor) {
  monitor.window.add(buildUs: 4000, rasterUs: 6000, spanUs: 10000, endUs: 1);
}

void main() {
  testWidgets('scene D defaults to the normal 400 px/s preset', (tester) async {
    final container = await _pump(tester);
    await _tap(tester, 'D · Four surfaces, scrolling');
    expect(
      container.read(glassPocScrollSpeedProvider),
      SistrumScrollSpeed.normal,
    );
    expect(find.text('Normal — 400 px/s'), findsOneWidget);
  });

  testWidgets('a speed change restarts from 0 and clears the measurement', (
    tester,
  ) async {
    final container = await _pump(tester);
    await _tap(tester, 'D · Four surfaces, scrolling');
    await tester.pump(const Duration(seconds: 3));
    expect(_list(tester).pixels, greaterThan(0));

    final monitor = container.read(perfFrameMonitorProvider);
    _addFrame(monitor);
    expect(monitor.window.count, 1);

    await _tap(tester, 'Fast — 900 px/s');
    expect(
      container.read(glassPocScrollSpeedProvider),
      SistrumScrollSpeed.fast,
    );
    expect(_list(tester).pixels, 0);
    expect(monitor.window.count, 0);
  });

  testWidgets('a renderer change keeps the speed, resets scroll and metrics', (
    tester,
  ) async {
    final container = await _pump(tester);
    await _tap(tester, 'D · Four surfaces, scrolling');
    await _tap(tester, 'Fast — 900 px/s');
    await tester.pump(const Duration(seconds: 2));

    final monitor = container.read(perfFrameMonitorProvider);
    _addFrame(monitor);
    await _tap(tester, 'New Full Glass');

    expect(
      container.read(glassPocScrollSpeedProvider),
      SistrumScrollSpeed.fast,
    );
    expect(container.read(glassPocModeProvider), SistrumGlassMode.newFullGlass);
    expect(_list(tester).pixels, 0);
    expect(monitor.window.count, 0);
  });

  testWidgets('leaving scene D stops the scroll and holds no ticker', (
    tester,
  ) async {
    await _pump(tester);
    await _tap(tester, 'D · Four surfaces, scrolling');
    await tester.pump(const Duration(seconds: 1));
    await _tap(tester, 'B · Four surfaces, static');
    await tester.pumpAndSettle();
    expect(_list(tester).pixels, 0);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('Start and Stop hold and resume the list', (tester) async {
    await _pump(tester);
    await _tap(tester, 'D · Four surfaces, scrolling');
    await tester.pump(const Duration(seconds: 1));
    await _tap(tester, 'Stop auto-scroll');
    final held = _list(tester).pixels;
    await tester.pump(const Duration(seconds: 2));
    expect(_list(tester).pixels, held);
    expect(find.text('Start auto-scroll'), findsOneWidget);

    await _tap(tester, 'Start auto-scroll');
    await tester.pump(const Duration(seconds: 1));
    expect(_list(tester).pixels, greaterThan(held));
  });

  testWidgets('Copy metrics names the path, the scene and the scroll speed', (
    tester,
  ) async {
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

    await _pump(tester);
    await _tap(tester, 'New FakeGlass');
    await _tap(tester, 'D · Four surfaces, scrolling');
    await tester.pump(const Duration(seconds: 1));
    await _tap(tester, 'Copy metrics');

    final text = copied!;
    expect(text, startsWith('sistrum-perf\nscreen=glass-poc\n'));
    expect(text, contains('glass_mode=New FakeGlass'));
    expect(text, contains('glass_render_path=fake_backdrop'));
    expect(text, contains('glass_fallback=false'));
    expect(text, contains('scene=D'));
    expect(text, contains('scroll_mode=auto'));
    expect(text, contains('scroll_speed_preset=normal'));
    expect(text, contains('scroll_speed_target=400'));
    expect(text, contains('scroll_speed_unit=logical_px_per_second'));
    expect(text, contains('scroll_boundary_behavior=reverse'));
    expect(text, contains('animated_background=off'));
    expect(text, contains('shared_backdrop=off'));
  });

  testWidgets(
    'Full Glass is never reported as full_gpu in the test VM without Flutter GPU',
    (tester) async {
      await _pump(tester);
      await _tap(tester, 'New Full Glass');
      await tester.pump(const Duration(seconds: 1));
      // The test VM has no Flutter GPU, so the package builds FakeGlass. The
      // probe must report that fallback, not a successful full path.
      expect(find.textContaining('glass_render_path=full_gpu'), findsNothing);
      final text = tester.widget<Text>(find.byKey(const Key('pathLine'))).data!;
      expect(text, isNot(contains('full_gpu')));
    },
  );
}
