import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart' as lgr;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;
import 'package:sistrum/providers/performance/glass_poc_mode_provider.dart';
import 'package:sistrum/screens/settings/developer/glass_poc_page.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_scene.dart';

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

Future<void> _tapChip(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(ChoiceChip, label);
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pump();
}

void main() {
  group('renderer selection', () {
    test('only the new renderer mode uses liquid_glass_renderer', () {
      for (final mode in SistrumGlassMode.values) {
        expect(
          mode.usesRenderer,
          mode == SistrumGlassMode.rendererGlass,
          reason: mode.label,
        );
      }
    });

    test(
      'the renderer is not the widgets package and has no widgets layer',
      () {
        expect(SistrumGlassMode.rendererGlass.usesLiquidGlass, isFalse);
        expect(SistrumGlassMode.rendererGlass.usesSharedLayer, isFalse);
      },
    );
  });

  group('scene configuration', () {
    test('the four scenes fix surface count, animation and scrolling', () {
      expect(SistrumGlassScene.oneSurface.surfaces, 1);
      expect(SistrumGlassScene.oneSurface.animated, isFalse);
      expect(SistrumGlassScene.oneSurface.scrolling, isFalse);

      expect(SistrumGlassScene.fourSurfaces.surfaces, 4);
      expect(SistrumGlassScene.fourSurfaces.animated, isFalse);
      expect(SistrumGlassScene.fourSurfaces.scrolling, isFalse);

      expect(SistrumGlassScene.animatedBackground.surfaces, 4);
      expect(SistrumGlassScene.animatedBackground.animated, isTrue);
      expect(SistrumGlassScene.animatedBackground.scrolling, isFalse);

      expect(SistrumGlassScene.scrollingContent.surfaces, 4);
      expect(SistrumGlassScene.scrollingContent.animated, isFalse);
      expect(SistrumGlassScene.scrollingContent.scrolling, isTrue);
    });
  });

  group('report label', () {
    test('names the renderer, scene, animation and shared state', () {
      final label = glassPocReportLabel(
        mode: SistrumGlassMode.rendererGlass,
        sharedBackdrop: true,
        scene: SistrumGlassScene.animatedBackground,
      );
      expect(label, contains('New renderer (liquid_glass_renderer)'));
      expect(label, contains('scene=C · Four surfaces, animated'));
      expect(label, contains('animated=on'));
      // The shared switch never applies to the renderer, so it reads off.
      expect(label, contains('shared=off'));
    });

    test('reports shared=on only for Reference Glass with the switch', () {
      final label = glassPocReportLabel(
        mode: SistrumGlassMode.referenceGlass,
        sharedBackdrop: true,
        scene: SistrumGlassScene.fourSurfaces,
      );
      expect(label, contains('shared=on'));
      expect(label, contains('animated=off'));
    });
  });

  group('renderer widget tree', () {
    testWidgets('each visible surface is one renderer glass shape', (
      tester,
    ) async {
      await _pump(tester);
      await _tapChip(tester, 'New renderer (liquid_glass_renderer)');
      await _tapChip(tester, 'B · Four surfaces, static');

      // Per-surface layers (see sistrum_renderer_glass.dart): no shared layer
      // from the page's scope, and one glass shape per visible surface.
      expect(find.byType(lgr.LiquidGlass), findsNWidgets(4));
      expect(find.byType(lgw.LiquidGlassLayer), findsNothing);
    });

    testWidgets('scene A shows a single renderer surface', (tester) async {
      await _pump(tester);
      await _tapChip(tester, 'New renderer (liquid_glass_renderer)');
      await _tapChip(tester, 'A · One surface, static');

      expect(find.byType(lgr.LiquidGlass), findsOneWidget);
      expect(find.text('Mini player'), findsOneWidget);
      expect(find.byIcon(Icons.search), findsNothing);
    });

    testWidgets('leaving the renderer removes its glass shapes', (
      tester,
    ) async {
      final container = await _pump(tester);
      await _tapChip(tester, 'New renderer (liquid_glass_renderer)');
      expect(find.byType(lgr.LiquidGlass), findsNWidgets(4));

      await _tapChip(tester, 'Transparent Baseline');
      expect(
        container.read(glassPocModeProvider),
        SistrumGlassMode.transparentBaseline,
      );
      expect(find.byType(lgr.LiquidGlass), findsNothing);
    });
  });

  group('scene animation state', () {
    testWidgets('the animated scene runs and leaving it stops', (tester) async {
      await _pump(tester);
      await _tapChip(tester, 'C · Four surfaces, animated');
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isTrue);

      await _tapChip(tester, 'B · Four surfaces, static');
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('the scrolling scene moves the list and resets on leaving', (
      tester,
    ) async {
      await _pump(tester);
      await _tapChip(tester, 'D · Four surfaces, scrolling');
      await tester.pump(const Duration(seconds: 3));
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrollable.position.pixels, greaterThan(0));

      await _tapChip(tester, 'B · Four surfaces, static');
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, 0);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
