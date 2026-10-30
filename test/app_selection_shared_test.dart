import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/glass/app_selection_shared.dart';

class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppSelectionForegroundScope>();
    return Text('count ${scope?.count ?? -1}');
  }
}

void main() {
  test('the selection pill keeps its shared corner radius', () {
    expect(kAppSelectionPillRadius, 32);
  });

  testWidgets('descendants read the selection values from the scope', (
    tester,
  ) async {
    final rowKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: AppSelectionForegroundScope(
          rowKey: rowKey,
          alignment: 0.5,
          count: 3,
          scaleX: 1,
          scaleY: 1,
          program: null,
          color: Colors.teal,
          child: const _Probe(),
        ),
      ),
    );
    expect(find.text('count 3'), findsOneWidget);
  });

  testWidgets('the scope notifies dependents when the count changes', (
    tester,
  ) async {
    final rowKey = GlobalKey();
    Widget scope(int count) => MaterialApp(
      home: AppSelectionForegroundScope(
        rowKey: rowKey,
        alignment: 0.5,
        count: count,
        scaleX: 1,
        scaleY: 1,
        program: null,
        color: Colors.teal,
        child: const _Probe(),
      ),
    );
    await tester.pumpWidget(scope(1));
    expect(find.text('count 1'), findsOneWidget);
    await tester.pumpWidget(scope(4));
    expect(find.text('count 4'), findsOneWidget);
  });
}
