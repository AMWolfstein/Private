import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:sistrum/providers/performance/glass_poc_mode_provider.dart';
import 'package:sistrum/screens/settings/developer/glass_poc_page.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_surface.dart';

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

bool _selected(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected;

void main() {
  testWidgets('starts on the transparent baseline with no glass layer', (
    tester,
  ) async {
    final container = await _pump(tester);

    expect(
      container.read(glassPocModeProvider),
      SistrumGlassMode.transparentBaseline,
    );
    expect(_selected(tester, 'Transparent Baseline'), isTrue);
    expect(find.byType(LiquidGlassLayer), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('each mode chip selects its mode and keeps the same content', (
    tester,
  ) async {
    final container = await _pump(tester);

    for (final mode in SistrumGlassMode.values) {
      await tester.tap(find.text(mode.label));
      await tester.pump();

      expect(container.read(glassPocModeProvider), mode, reason: mode.label);
      expect(_selected(tester, mode.label), isTrue, reason: mode.label);
      // Only Liquid Glass has a shared layer. Reference Glass requests premium
      // quality with its own layer on each of its four surfaces.
      expect(
        find.descendant(
          of: find.byType(SistrumGlassScope),
          matching: find.byType(LiquidGlassLayer),
        ),
        mode == SistrumGlassMode.liquidGlass ? findsOneWidget : findsNothing,
        reason: mode.label,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is GlassContainer && w.quality == GlassQuality.premium,
        ),
        mode == SistrumGlassMode.referenceGlass
            ? findsNWidgets(4)
            : findsNothing,
        reason: mode.label,
      );
      expect(
        find.byType(BackdropFilter),
        mode == SistrumGlassMode.basicBlur ? findsWidgets : findsNothing,
        reason: mode.label,
      );
      expect(find.text('Mini player'), findsOneWidget);
      expect(
        find.text('Track 1 — scrolling content under glass'),
        findsOneWidget,
      );
    }
  });

  testWidgets('the header and tab bar icons are tappable in glass mode', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Reference Glass'));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.search).first);
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the animated background starts and stops cleanly', (
    tester,
  ) async {
    await _pump(tester);

    await tester.ensureVisible(
      find.widgetWithText(ChoiceChip, 'C · Four surfaces, animated'),
    );

    await tester.tap(
      find.widgetWithText(ChoiceChip, 'C · Four surfaces, animated'),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.ensureVisible(
      find.widgetWithText(ChoiceChip, 'B · Four surfaces, static'),
    );

    await tester.tap(
      find.widgetWithText(ChoiceChip, 'B · Four surfaces, static'),
    );
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('leaving the page disposes the background animation', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: _PageHost())),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(ChoiceChip, 'C · Four surfaces, animated'),
    );
    await tester.tap(
      find.widgetWithText(ChoiceChip, 'C · Four surfaces, animated'),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.hasRunningAnimations, isFalse);
  });
}

class _PageHost extends StatelessWidget {
  const _PageHost();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const GlassPocPage())),
        child: const Text('open'),
      ),
    );
  }
}
