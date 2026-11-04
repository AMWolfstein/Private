import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1455/g1455.dart' show GlassSurface, GlassTravel;
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/glass/selection/app_selection_pill.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_thumb.dart';

const _rest = Size(37, 24);
const _active = Size(58, 38);

Future<void> _thumb(
  WidgetTester tester, {
  required double x,
  required bool held,
  bool placing = false,
  bool reduceMotion = false,
}) => tester.pumpWidget(
  ProviderScope(
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Center(
          child: SizedBox(
            width: 400,
            height: 48,
            child: AppGlassThumb(
              center: Offset(x, 24),
              held: held,
              placing: placing,
              restSize: _rest,
              activeSize: _active,
            ),
          ),
        ),
      ),
    ),
  ),
);

Size _glass(WidgetTester tester) =>
    tester.getSize(find.byKey(kAppGlassThumbKey));

Future<void> _pill(WidgetTester tester, {required int selected}) =>
    tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 56,
                child: AppSelectionPill(
                  labels: const ['A', 'B', 'C'],
                  selectedIndex: selected,
                  onChanged: (_) {},
                  glassInteraction: true,
                  contrastBlocked: false,
                  itemBuilder: (context, index, selected) =>
                      Center(child: Text('$index')),
                ),
              ),
            ),
          ),
        ),
      ),
    );

/// The resting pill's alignment, which follows the slide.
double _pillAlignment(WidgetTester tester) {
  final align = tester.widget<Align>(
    find
        .ancestor(
          of: find.byType(FractionallySizedBox).first,
          matching: find.byType(Align),
        )
        .first,
  );
  return (align.alignment as AlignmentDirectional).start;
}

void main() {
  group('AppGlassThumb (g1455 drop motion)', () {
    testWidgets('lifts over 180 ms, eased, and settles back', (tester) async {
      await _thumb(tester, x: 100, held: false);
      expect(find.byKey(kAppGlassThumbKey), findsNothing);

      await _thumb(tester, x: 100, held: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      final halfway = _glass(tester);
      expect(halfway.width, greaterThan(_rest.width));
      expect(halfway.width, lessThan(_active.width));

      await tester.pump(const Duration(milliseconds: 100));
      expect(_glass(tester), _active);

      await _thumb(tester, x: 100, held: false);
      await tester.pump();
      await tester.pump(kAppGlassThumbLiftDuration);
      // At rest the glass is out of the tree: nothing is read.
      expect(find.byKey(kAppGlassThumbKey), findsNothing);
    });

    testWidgets('stretches while it speeds up and recovers when still', (
      tester,
    ) async {
      await _thumb(tester, x: 60, held: true);
      await tester.pumpAndSettle();
      var widest = 0.0;
      for (var x = 60.0; x <= 300; x += 30) {
        await _thumb(tester, x: x, held: true);
        await tester.pump(const Duration(milliseconds: 16));
        widest = widest > _glass(tester).width ? widest : _glass(tester).width;
      }
      expect(widest, greaterThan(_active.width));
      await tester.pumpAndSettle();
      expect(_glass(tester), _active);
    });

    testWidgets('a tap placing the thumb does not stretch it', (tester) async {
      await _thumb(tester, x: 60, held: true);
      await tester.pumpAndSettle();
      await _thumb(tester, x: 300, held: true, placing: true);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(_glass(tester), _active);
      }
    });

    testWidgets('reduced motion lifts at once and never stretches', (
      tester,
    ) async {
      await _thumb(tester, x: 60, held: false, reduceMotion: true);
      await _thumb(tester, x: 60, held: true, reduceMotion: true);
      await tester.pump();
      expect(_glass(tester), _active);
      for (var x = 60.0; x <= 300; x += 60) {
        await _thumb(tester, x: x, held: true, reduceMotion: true);
        await tester.pump(const Duration(milliseconds: 16));
        expect(_glass(tester), _active);
      }
    });

    testWidgets('moves inside a travel region of its own', (tester) async {
      await _thumb(tester, x: 100, held: true);
      await tester.pumpAndSettle();
      expect(
        find.ancestor(
          of: find.byKey(kAppGlassThumbKey),
          matching: find.byType(GlassTravel),
        ),
        findsOneWidget,
      );
    });
  });

  group('AppSelectionPill (g1455 tab bar springs)', () {
    testWidgets('a press lifts on a spring that rises past held', (
      tester,
    ) async {
      await _pill(tester, selected: 0);
      final gesture = await tester.startGesture(
        tester.getTopLeft(find.byType(AppSelectionPill)) + const Offset(50, 28),
      );
      var largest = 0.0;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final glass = find.byType(GlassSurface);
        if (glass.evaluate().isEmpty) continue;
        final transform = tester.widget<Transform>(
          find.ancestor(of: glass, matching: find.byType(Transform)).first,
        );
        final scale = transform.transform.storage[0];
        if (scale > largest) largest = scale;
      }
      // Held is 1.28 across; the spring overshoots it before settling.
      expect(largest, greaterThan(1.28));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(GlassSurface), findsNothing);
    });

    testWidgets('a new selection slides on a spring and lands exactly', (
      tester,
    ) async {
      await _pill(tester, selected: 0);
      expect(_pillAlignment(tester), -1);
      await _pill(tester, selected: 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final moving = _pillAlignment(tester);
      expect(moving, greaterThan(-1));
      expect(moving, lessThan(1));
      await tester.pumpAndSettle();
      expect(_pillAlignment(tester), 1);
    });
  });
}
