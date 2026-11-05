import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_auto_scroll.dart';

const double _maxExtent = 1000;

Future<void> _pumpList(WidgetTester tester, ScrollController c) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView.builder(
          controller: c,
          itemCount: 60,
          itemExtent: 100,
          itemBuilder: (_, i) => SizedBox(height: 100, child: Text('$i')),
        ),
      ),
    ),
  );
}

/// Pumps [frames] frames of [step] each, so elapsed time is exact.
Future<void> _frames(WidgetTester tester, int frames, Duration step) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

void main() {
  group('speed presets', () {
    test('the three presets are 150, 400 and 900 logical px per second', () {
      expect(SistrumScrollSpeed.slow.pxPerSecond, 150);
      expect(SistrumScrollSpeed.normal.pxPerSecond, 400);
      expect(SistrumScrollSpeed.fast.pxPerSecond, 900);
      expect(SistrumScrollSpeed.values, hasLength(3));
    });

    test('labels state the speed in px/s', () {
      expect(SistrumScrollSpeed.slow.label, contains('150 px/s'));
      expect(SistrumScrollSpeed.normal.label, contains('400 px/s'));
      expect(SistrumScrollSpeed.fast.label, contains('900 px/s'));
    });
  });

  group('offset function', () {
    test('displacement is speed times seconds, in logical pixels', () {
      expect(
        sistrumAutoScrollOffset(
          seconds: 1,
          pxPerSecond: 400,
          maxExtent: _maxExtent,
        ),
        400,
      );
      expect(
        sistrumAutoScrollOffset(
          seconds: 0.25,
          pxPerSecond: 900,
          maxExtent: _maxExtent,
        ),
        225,
      );
    });

    test('reverses at the end and returns to the start without a jump', () {
      // At 1000 px/s the end (1000 px) is reached at 1 s, then the list
      // comes back: 500 px at 1.5 s, and the start again at 2 s.
      double at(double s) => sistrumAutoScrollOffset(
        seconds: s,
        pxPerSecond: 1000,
        maxExtent: _maxExtent,
      );
      expect(at(1), 1000);
      expect(at(1.5), 500);
      expect(at(2), 0);
      expect(at(2.5), 500);
    });

    test('the offset never jumps: consecutive steps are at most speed*dt', () {
      const speed = 400.0;
      const dt = 1 / 120;
      var previous = sistrumAutoScrollOffset(
        seconds: 0,
        pxPerSecond: speed,
        maxExtent: _maxExtent,
      );
      for (var t = dt; t < 12; t += dt) {
        final next = sistrumAutoScrollOffset(
          seconds: t,
          pxPerSecond: speed,
          maxExtent: _maxExtent,
        );
        expect((next - previous).abs(), lessThanOrEqualTo(speed * dt + 1e-6));
        previous = next;
      }
    });

    test('direction flips at the turning points', () {
      bool down(double s) => sistrumAutoScrollMovingDown(
        seconds: s,
        pxPerSecond: 1000,
        maxExtent: _maxExtent,
      );
      expect(down(0.5), isTrue);
      expect(down(1.5), isFalse);
      expect(down(2.5), isTrue);
    });

    test('an unmeasured extent holds the offset at 0', () {
      expect(
        sistrumAutoScrollOffset(seconds: 5, pxPerSecond: 400, maxExtent: 0),
        0,
      );
    });
  });

  group('scroller on a real list', () {
    testWidgets('moves by speed times elapsed frame time, not frame count', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pumpList(tester, controller);

      final scroller = SistrumAutoScroller(
        vsync: TestVSync(),
        controller: controller,
      );
      addTearDown(scroller.dispose);

      scroller.restart();
      await tester.pump(); // the first frame: elapsed 0
      // Uneven frames total 156 ms, so the expected offset is 62.4 px.
      await tester.pump(const Duration(milliseconds: 7));
      await tester.pump(const Duration(milliseconds: 33));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.position.pixels, closeTo(62.4, 0.5));
      scroller.stop();
    });

    testWidgets('actual speed is measured after warm-up and matches target', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pumpList(tester, controller);
      final scroller = SistrumAutoScroller(
        vsync: TestVSync(),
        controller: controller,
      );
      addTearDown(scroller.dispose);

      scroller.restart();
      await tester.pump();
      await _frames(tester, 180, const Duration(microseconds: 16667));
      final status = scroller.status();
      expect(status.measuring, isTrue);
      expect(status.running, isTrue);
      expect(status.direction, 'down');
      expect(status.actualPxPerSecond, isNotNull);
      expect(status.actualPxPerSecond!, closeTo(400, 4));
      scroller.stop();
    });

    testWidgets('no speed is reported before warm-up ends', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pumpList(tester, controller);
      final scroller = SistrumAutoScroller(
        vsync: TestVSync(),
        controller: controller,
      );
      addTearDown(scroller.dispose);

      scroller.restart();
      await tester.pump();
      await _frames(tester, 60, const Duration(milliseconds: 16));
      final status = scroller.status();
      expect(status.measuring, isFalse);
      expect(status.actualPxPerSecond, isNull);
      expect(status.samples, 0);
      scroller.stop();
    });

    testWidgets('a turn at the end is counted in the sample window', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pumpList(tester, controller);
      final scroller = SistrumAutoScroller(
        vsync: TestVSync(),
        controller: controller,
        speed: SistrumScrollSpeed.fast,
      );
      addTearDown(scroller.dispose);

      scroller.restart();
      await tester.pump();
      // Fast turns at maxExtent / 900 px/s, about 6 s here, so 7 s of frames
      // includes at least one turn after the 2 s warm-up.
      await _frames(tester, 420, const Duration(milliseconds: 16));
      final status = scroller.status();
      expect(status.boundaryTransitions, greaterThanOrEqualTo(1));
      expect(
        controller.position.pixels,
        lessThan(controller.position.maxScrollExtent),
      );
      scroller.stop();
    });

    testWidgets('stop holds the offset and resume continues from it', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pumpList(tester, controller);
      final scroller = SistrumAutoScroller(
        vsync: TestVSync(),
        controller: controller,
      );
      addTearDown(scroller.dispose);

      scroller.restart();
      await tester.pump();
      await _frames(tester, 100, const Duration(milliseconds: 10)); // 1 s
      scroller.stop();
      final held = controller.position.pixels;
      expect(held, closeTo(400, 0.5));

      // Stopped: no ticker, so the offset does not move however long we wait.
      await tester.pump(const Duration(seconds: 3));
      expect(controller.position.pixels, held);
      expect(tester.hasRunningAnimations, isFalse);

      scroller.start();
      await tester.pump();
      await _frames(tester, 100, const Duration(milliseconds: 10)); // +1 s
      expect(controller.position.pixels, closeTo(800, 0.5));
      scroller.stop();
    });

    testWidgets('restart returns to offset 0 and clears the samples', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pumpList(tester, controller);
      final scroller = SistrumAutoScroller(
        vsync: TestVSync(),
        controller: controller,
      );
      addTearDown(scroller.dispose);

      scroller.restart();
      await tester.pump();
      await _frames(tester, 180, const Duration(microseconds: 16667));
      expect(scroller.status().samples, greaterThan(0));

      scroller.setSpeed(SistrumScrollSpeed.slow);
      await tester.pump();
      final status = scroller.status();
      expect(status.speed, SistrumScrollSpeed.slow);
      expect(status.measuring, isFalse);
      expect(status.samples, 0);
      expect(status.actualPxPerSecond, isNull);
      expect(controller.position.pixels, 0);
      scroller.stop();
    });

    testWidgets('sampling waits for the readiness gate', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pumpList(tester, controller);
      var ready = false;
      final scroller = SistrumAutoScroller(
        vsync: TestVSync(),
        controller: controller,
        measurementReady: () => ready,
      );
      addTearDown(scroller.dispose);

      scroller.restart();
      await tester.pump();
      await _frames(tester, 180, const Duration(microseconds: 16667));
      expect(scroller.status().measuring, isFalse);
      // The list still moved: the gate holds samples, not the motion.
      expect(controller.position.pixels, greaterThan(0));

      ready = true;
      await _frames(tester, 10, const Duration(milliseconds: 16));
      expect(scroller.status().measuring, isTrue);
      scroller.stop();
    });

    testWidgets('disposing a running scroller leaves no active ticker', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pumpList(tester, controller);
      final scroller = SistrumAutoScroller(
        vsync: TestVSync(),
        controller: controller,
      );

      scroller.restart();
      await tester.pump(const Duration(milliseconds: 100));
      scroller.dispose();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('whole-interval totals for the benchmark', () {
    testWidgets('overall speed covers the whole interval, not a window', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pumpList(tester, controller);
      final scroller = SistrumAutoScroller(
        vsync: TestVSync(),
        controller: controller,
        speed: SistrumScrollSpeed.fast,
        warmupSeconds: 0.1,
      );
      addTearDown(scroller.dispose);

      scroller.restart();
      await tester.pump();
      // 5 s of 10 ms frames: far more than the 300-sample window holds.
      await _frames(tester, 500, const Duration(milliseconds: 10));
      final status = scroller.status();
      expect(status.measuring, isTrue);
      expect(status.measuredSeconds, closeTo(4.9, 0.05));
      expect(status.overallPxPerSecond, closeTo(900, 2));
      expect(status.totalBoundaryTurns, 0);
      scroller.stop();
    });

    testWidgets('warm-up length is the configured value', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pumpList(tester, controller);
      final scroller = SistrumAutoScroller(
        vsync: TestVSync(),
        controller: controller,
        warmupSeconds: 1.5,
      );
      addTearDown(scroller.dispose);

      scroller.restart();
      await tester.pump();
      await _frames(tester, 100, const Duration(milliseconds: 10)); // 1 s
      expect(scroller.status().measuring, isFalse);
      await _frames(tester, 100, const Duration(milliseconds: 10)); // 2 s
      expect(scroller.status().measuring, isTrue);
      scroller.stop();
    });
  });

  group('distance, detachment and tick gaps during measurement', () {
    testWidgets(
      'measured distance is the displacement applied since measurement',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await _pumpList(tester, controller);
        final scroller = SistrumAutoScroller(
          vsync: TestVSync(),
          controller: controller,
          speed: SistrumScrollSpeed.fast,
          warmupSeconds: 0.1,
        );
        addTearDown(scroller.dispose);

        scroller.restart();
        await tester.pump();
        await _frames(tester, 300, const Duration(milliseconds: 10)); // 3 s
        final status = scroller.status();
        expect(status.measuredPathPx, closeTo(900 * status.measuredSeconds, 2));
        expect(status.measureTicks, greaterThan(250));
        expect(status.unattachedTicks, 0);
        expect(status.maxTickGapSeconds, lessThan(0.05));
        expect(status.maxExtent, greaterThan(0));
        scroller.stop();
      },
    );

    testWidgets('ticks with no attached list are counted as unattached', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pumpList(tester, controller);
      final scroller = SistrumAutoScroller(
        vsync: TestVSync(),
        controller: controller,
        warmupSeconds: 0.1,
      );
      addTearDown(scroller.dispose);

      scroller.restart();
      await tester.pump();
      await _frames(tester, 50, const Duration(milliseconds: 10));
      expect(scroller.status().measuring, isTrue);

      // Take the list away while the scroller keeps ticking.
      await tester.pumpWidget(const SizedBox());
      await _frames(tester, 20, const Duration(milliseconds: 10));
      expect(scroller.status().unattachedTicks, greaterThan(0));
      scroller.stop();
    });

    testWidgets('a long frame gap while scrolling is recorded as a tick gap', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pumpList(tester, controller);
      final scroller = SistrumAutoScroller(
        vsync: TestVSync(),
        controller: controller,
        warmupSeconds: 0.1,
      );
      addTearDown(scroller.dispose);

      scroller.restart();
      await tester.pump();
      await _frames(tester, 50, const Duration(milliseconds: 10));
      // One 1.5 s frame: the scroller saw no ticks for that long.
      await tester.pump(const Duration(milliseconds: 1500));
      await _frames(tester, 10, const Duration(milliseconds: 10));
      expect(scroller.status().maxTickGapSeconds, closeTo(1.5, 0.05));
      scroller.stop();
    });
  });
}
