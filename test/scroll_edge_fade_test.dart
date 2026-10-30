import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/shell/scroll_edge_fade.dart';

double _fadeOpacity(WidgetTester tester) =>
    tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

void main() {
  testWidgets('the fade shows while more content lies below', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollEdgeFade(
            child: ListView(
              children: [for (var i = 0; i < 40; i++) SizedBox(height: 100, child: Text('Row $i'))],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_fadeOpacity(tester), 1);
  });

  testWidgets('the fade hides once the list is scrolled to its end', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollEdgeFade(
            child: ListView(
              controller: controller,
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(height: 100, child: Text('Row $i')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(_fadeOpacity(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short list never shows the fade', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollEdgeFade(
            child: ListView(children: const [SizedBox(height: 40)]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_fadeOpacity(tester), 0);
  });
}
