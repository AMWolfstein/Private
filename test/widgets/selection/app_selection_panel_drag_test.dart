import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/selection/app_selection_panel_drag.dart';

Widget _panel({required VoidCallback onClose}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.bottomCenter,
      child: AppSelectionPanelDrag(
        onClose: onClose,
        header: const SizedBox(
          height: 56,
          width: 390,
          child: Center(child: Text('3 selected')),
        ),
        bottomPadding: 0,
        surfaceBuilder: (child) => child,
        children: const [
          SizedBox(height: 120, width: 390, child: Text('Add to playlist')),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('the selection header and its actions are both shown at rest', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_panel(onClose: () {}));
    await tester.pumpAndSettle();
    expect(find.text('3 selected'), findsOneWidget);
    expect(find.text('Add to playlist'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pulling the actions away keeps the header on screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var closed = 0;
    await tester.pumpWidget(_panel(onClose: () => closed++));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Add to playlist')),
    );
    await gesture.moveBy(const Offset(0, 80));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('3 selected'), findsOneWidget);
    expect(tester.getTopLeft(find.text('3 selected')).dy, lessThan(844));
    expect(closed, 0);
    expect(tester.takeException(), isNull);
  });
}
