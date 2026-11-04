import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/providers/performance/perf_hud_settings_provider.dart';
import 'package:sistrum/services/performance/perf_frame_monitor.dart';
import 'package:sistrum/widgets/performance/perf_hud_overlay.dart';

class _FixedSettings extends PerfHudSettingsNotifier {
  _FixedSettings(this.initial);
  final PerfHudSettings initial;

  @override
  PerfHudSettings build() => initial;
}

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  PerfHudSettings settings = const PerfHudSettings(enabled: true),
  Size size = const Size(400, 800),
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      perfHudSettingsProvider.overrideWith(() => _FixedSettings(settings)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: const MaterialApp(
          home: Stack(children: [SizedBox.expand(), PerfHudOverlay()]),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

Finder get _panel => find.descendant(
  of: find.byType(PerfHudOverlay),
  matching: find.byType(GestureDetector),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a disabled HUD shows nothing and keeps the callback off', (
    tester,
  ) async {
    final container = await _mount(tester, settings: const PerfHudSettings());
    expect(_panel, findsNothing);
    expect(container.read(perfFrameMonitorProvider).isRunning, isFalse);
  });

  testWidgets('an enabled HUD starts the callback and shows compact metrics', (
    tester,
  ) async {
    final container = await _mount(tester);
    expect(container.read(perfFrameMonitorProvider).isRunning, isTrue);
    expect(find.textContaining('FPS'), findsOneWidget);
    expect(find.textContaining('J '), findsOneWidget);
  });

  testWidgets('tapping the panel toggles between compact and expanded', (
    tester,
  ) async {
    await _mount(tester);
    expect(find.text('Reset'), findsNothing);
    await tester.tap(_panel);
    await tester.pump();
    expect(find.text('Reset'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(_panel.first);
    await tester.pump();
    expect(find.text('Reset'), findsNothing);
  });

  testWidgets('dragging moves the panel and clamps it to the screen', (
    tester,
  ) async {
    final container = await _mount(tester);
    await tester.drag(_panel, const Offset(-2000, 2000));
    await tester.pump();
    final saved = container.read(perfHudSettingsProvider).position;
    expect(saved, isNotNull);
    // Clamped to the safe area: left margin 8, bottom margin 8 above the panel.
    expect(saved!.dx, 8);
    expect(saved.dy, greaterThan(0));
    expect(saved.dy, lessThanOrEqualTo(800));
  });

  testWidgets('the dragged position is persisted across a restart', (
    tester,
  ) async {
    final container = await _mount(tester);
    await tester.drag(_panel, const Offset(-100, 50));
    await tester.pump();
    final saved = container.read(perfHudSettingsProvider).position!;
    await tester.pump(const Duration(milliseconds: 10));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('perf_hud_dx'), saved.dx);
    expect(prefs.getDouble('perf_hud_dy'), saved.dy);
  });

  testWidgets('Reset clears the window and the total frame count', (
    tester,
  ) async {
    final container = await _mount(tester);
    final monitor = container.read(perfFrameMonitorProvider);
    monitor.window.add(buildUs: 1000, rasterUs: 1000, spanUs: 2000, endUs: 1);
    await tester.tap(_panel);
    await tester.pump();
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(monitor.window.count, 0);
    expect(monitor.window.totalFrames, 0);
  });

  testWidgets('Copy places the structured report on the clipboard', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final container = await _mount(tester);
    container
        .read(perfFrameMonitorProvider)
        .window
        .add(buildUs: 2000, rasterUs: 3000, spanUs: 5000, endUs: 16667);
    await tester.tap(_panel);
    await tester.pump();
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied, startsWith('sistrum-perf\nscreen=unknown\nhz=60\n'));
    expect(copied, contains('frames=0'));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('Close disables the HUD and releases the callback', (
    tester,
  ) async {
    final container = await _mount(tester);
    expect(container.read(perfFrameMonitorProvider).isRunning, isTrue);
    await tester.tap(_panel);
    await tester.pump();
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(container.read(perfHudSettingsProvider).enabled, isFalse);
    expect(container.read(perfFrameMonitorProvider).isRunning, isFalse);
    expect(_panel, findsNothing);
  });
}
