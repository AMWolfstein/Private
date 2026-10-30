import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/animation_indicators.dart';

void main() {
  testWidgets('a selected checkbox shows its check mark', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedSelectionCheckbox(
            visible: true,
            selected: true,
            colorScheme: const ColorScheme.dark(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('an unselected checkbox has no check mark', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedSelectionCheckbox(
            visible: true,
            selected: false,
            colorScheme: const ColorScheme.dark(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('a hidden checkbox is scaled to nothing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedSelectionCheckbox(
            visible: false,
            selected: false,
            colorScheme: const ColorScheme.dark(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 0);
  });

  testWidgets('a rising badge count bumps the badge scale', (tester) async {
    Widget badge(int count) => MaterialApp(
      home: Scaffold(
        body: AnimatedBadge(count: count, child: const Text('badge')),
      ),
    );
    await tester.pumpWidget(badge(1));
    await tester.pumpWidget(badge(2));
    await tester.pump(const Duration(milliseconds: 60));
    final scale = tester.widget<ScaleTransition>(
      find.descendant(
        of: find.byType(AnimatedBadge),
        matching: find.byType(ScaleTransition),
      ),
    );
    expect(scale.scale.value, greaterThan(1));
    await tester.pumpAndSettle();
    expect(scale.scale.value, closeTo(1, 0.001));
  });

  testWidgets('a falling badge count does not animate', (tester) async {
    Widget badge(int count) => MaterialApp(
      home: Scaffold(
        body: AnimatedBadge(count: count, child: const Text('badge')),
      ),
    );
    await tester.pumpWidget(badge(3));
    await tester.pumpWidget(badge(1));
    await tester.pump(const Duration(milliseconds: 60));
    final scale = tester.widget<ScaleTransition>(
      find.descendant(
        of: find.byType(AnimatedBadge),
        matching: find.byType(ScaleTransition),
      ),
    );
    expect(scale.scale.value, closeTo(1, 0.001));
  });
}
