import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/selection/app_animated_selection_bar.dart';

void main() {
  testWidgets('a selection bar starts hidden and fades in with its child', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AnimatedSelectionBottomBar(child: Text('3 selected')),
        ),
      ),
    );
    final fade = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byType(AnimatedSelectionBottomBar),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fade.opacity.value, 0);

    await tester.pumpAndSettle();
    expect(fade.opacity.value, 1);
    expect(find.text('3 selected'), findsOneWidget);
  });

  testWidgets('the bar slides up from slightly below its resting place', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AnimatedSelectionBottomBar(child: Text('Bar'))),
      ),
    );
    final slide = tester.widget<SlideTransition>(
      find.descendant(
        of: find.byType(AnimatedSelectionBottomBar),
        matching: find.byType(SlideTransition),
      ),
    );
    expect(slide.position.value.dy, greaterThan(0));
    await tester.pumpAndSettle();
    expect(slide.position.value, Offset.zero);
  });
}
