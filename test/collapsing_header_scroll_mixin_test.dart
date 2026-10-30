import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/screens/library/collapsing_header_scroll_mixin.dart';

class _Screen extends StatefulWidget {
  const _Screen();

  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen> with CollapsingHeaderScrollMixin {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListView.builder(
      controller: scrollController,
      itemCount: 100,
      itemBuilder: (_, index) => SizedBox(height: 50, child: Text('Item $index')),
    ),
  );
}

void main() {
  testWidgets('the title appears in the toolbar once the header scrolls away', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: _Screen()));
    await tester.pumpAndSettle();
    final state = tester.state<_ScreenState>(find.byType(_Screen));
    expect(state.showTitleInAppBar, isFalse);

    // The threshold is the expanded height minus the toolbar and a margin.
    state.scrollController.jumpTo(600);
    await tester.pumpAndSettle();
    expect(state.showTitleInAppBar, isTrue);

    state.scrollController.jumpTo(0);
    await tester.pumpAndSettle();
    expect(state.showTitleInAppBar, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the expanded header height stays within its bounds', (
    tester,
  ) async {
    for (final height in [300.0, 844.0, 2000.0]) {
      tester.view.physicalSize = Size(390, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: _Screen()));
      final state = tester.state<_ScreenState>(find.byType(_Screen));
      final expanded = state.calculateExpandedHeight(
        tester.element(find.byType(_Screen)),
      );
      expect(expanded, inInclusiveRange(400, 580));
    }
  });
}
