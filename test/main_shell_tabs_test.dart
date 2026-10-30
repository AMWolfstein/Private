import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/screens/main_shell_tabs.dart';

void main() {
  testWidgets('a tab navigator shows its first page', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: TabNavigator(
          navigatorKey: key,
          heroAnimationsEnabled: true,
          child: const Scaffold(body: Text('Tab root')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tab root'), findsOneWidget);
    expect(key.currentState, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pages pushed inside a tab stack above its root', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: TabNavigator(
          navigatorKey: key,
          heroAnimationsEnabled: false,
          child: const Scaffold(body: Text('Tab root')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    key.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Detail')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Detail'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
