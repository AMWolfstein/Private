import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/screens/shell/main_shell_tabs.dart';

void main() {
  testWidgets(
    'tab heroes fly by default and release their controller on disposal',
    (tester) async {
      final key = GlobalKey<NavigatorState>();
      var flights = 0;
      Widget artwork() => Hero(
        tag: 'local-artwork',
        flightShuttleBuilder: (context, animation, direction, from, to) {
          flights++;
          return const SizedBox.square(dimension: 40);
        },
        child: const SizedBox.square(dimension: 40),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TabNavigator(
            navigatorKey: key,
            child: Scaffold(body: artwork()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final controller = key.currentState!.widget.observers
          .whereType<HeroController>()
          .single;
      expect(controller.navigator, key.currentState);
      key.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => Scaffold(body: artwork())),
      );
      await tester.pumpAndSettle();
      expect(flights, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      expect(controller.navigator, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('a tab navigator shows its first page', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: TabNavigator(
          navigatorKey: key,
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
