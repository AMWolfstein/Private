import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/widgets/animation_utils.dart';

void main() {
  testWidgets('reduced motion shows list content immediately', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: StaggeredListItem(index: 8, child: Text('Album')),
        ),
      ),
    );
    expect(find.text('Album').hitTestable(), findsOneWidget);
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('only the first reveal animates, never a row scrolled in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemCount: 14,
          itemBuilder: (context, index) => StaggeredListItem(
            index: index,
            child: SizedBox(height: 100, child: Text('Song ${index + 1}')),
          ),
        ),
      ),
    );
    // A row animates while it is not fully shown yet.
    bool animates(String title) => tester
        .widgetList<Opacity>(
          find.ancestor(of: find.text(title), matching: find.byType(Opacity)),
        )
        .any((opacity) => opacity.opacity < 1);
    expect(animates('Song 1'), isTrue);
    await tester.pumpAndSettle();
    expect(animates('Song 1'), isFalse);

    // Rows the list builds while scrolled appear at once, the last as well
    // as those before it, and rows scrolled back to do not replay.
    Future<void> scrollTo(double target) async {
      final step = target > controller.offset ? 50.0 : -50.0;
      while ((target - controller.offset).abs() >= 50) {
        controller.jumpTo(controller.offset + step);
        await tester.pump();
        for (final element in find.byType(Text).evaluate()) {
          final title = (element.widget as Text).data!;
          expect(animates(title), isFalse, reason: '$title at $target');
        }
      }
    }

    await scrollTo(1000);
    expect(find.text('Song 14'), findsOneWidget);
    await scrollTo(0);
    expect(find.text('Song 1'), findsOneWidget);
  });
}
