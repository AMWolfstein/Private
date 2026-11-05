import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:sistrum/providers/performance/glass_poc_mode_provider.dart';
import 'package:sistrum/screens/settings/developer/glass_poc_page.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_surface.dart';

Widget _scope(SistrumGlassMode mode, {required bool sharedBackdrop}) {
  return MaterialApp(
    home: Scaffold(
      body: SistrumGlassScope(
        mode: mode,
        sharedBackdrop: sharedBackdrop,
        child: const Text('Content'),
      ),
    ),
  );
}

void main() {
  group('shared backdrop group', () {
    test('applies only to Reference Glass with the switch on', () {
      for (final mode in SistrumGlassMode.values) {
        for (final on in [true, false]) {
          expect(
            sharedBackdropApplies(mode, on),
            on && mode == SistrumGlassMode.referenceGlass,
            reason: '${mode.label} switch=$on',
          );
        }
      }
    });

    testWidgets('Reference Glass wraps its scope in a group when on', (
      tester,
    ) async {
      await tester.pumpWidget(
        _scope(SistrumGlassMode.referenceGlass, sharedBackdrop: true),
      );
      expect(find.byType(GlassBackdropGroup), findsOneWidget);
      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('no group when the switch is off', (tester) async {
      await tester.pumpWidget(
        _scope(SistrumGlassMode.referenceGlass, sharedBackdrop: false),
      );
      expect(find.byType(GlassBackdropGroup), findsNothing);
    });

    testWidgets('Liquid Glass and Basic Blur never get a group', (
      tester,
    ) async {
      for (final mode in [
        SistrumGlassMode.liquidGlass,
        SistrumGlassMode.basicBlur,
        SistrumGlassMode.transparentBaseline,
      ]) {
        await tester.pumpWidget(_scope(mode, sharedBackdrop: true));
        expect(
          find.byType(GlassBackdropGroup),
          findsNothing,
          reason: mode.label,
        );
        expect(find.text('Content'), findsOneWidget, reason: mode.label);
      }
    });
  });

  group('rendering path label', () {
    test('names the shared path only where it applies', () {
      expect(
        glassPocPathLabel(
          SistrumGlassMode.referenceGlass,
          sharedBackdrop: true,
        ),
        'Reference Glass (shared backdrop)',
      );
      expect(
        glassPocPathLabel(
          SistrumGlassMode.referenceGlass,
          sharedBackdrop: false,
        ),
        'Reference Glass',
      );
      expect(
        glassPocPathLabel(SistrumGlassMode.liquidGlass, sharedBackdrop: true),
        'Liquid Glass',
      );
    });
  });

  group('switch state', () {
    test('defaults to off and can be set back', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(glassPocSharedBackdropProvider), isFalse);
      container.read(glassPocSharedBackdropProvider.notifier).set(true);
      expect(container.read(glassPocSharedBackdropProvider), isTrue);
      container.read(glassPocSharedBackdropProvider.notifier).set(false);
      expect(container.read(glassPocSharedBackdropProvider), isFalse);
    });

    testWidgets('the page switch selects the grouped path for Reference only', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(glassPocModeProvider.notifier)
          .select(SistrumGlassMode.referenceGlass);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GlassPocPage()),
        ),
      );

      expect(find.byType(GlassBackdropGroup), findsNothing);
      final switchFinder = find.widgetWithText(
        SwitchListTile,
        'Shared backdrop group (Reference Glass only)',
      );
      await tester.ensureVisible(switchFinder);
      await tester.tap(switchFinder);
      await tester.pump();

      expect(container.read(glassPocSharedBackdropProvider), isTrue);
      expect(find.byType(GlassBackdropGroup), findsOneWidget);
    });
  });
}
