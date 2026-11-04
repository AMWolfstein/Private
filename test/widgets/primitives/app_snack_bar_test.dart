
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/primitives/app_snack_bar.dart';

void main() {
  for (final sistrum in [true]) {
    testWidgets(
      'new messages replace old ones and still dismiss (Sistrum: $sistrum)',
      (tester) async {
        late BuildContext messageContext;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: sistrum ? AppTheme.build(Brightness.dark) : ThemeData(),
              builder: (_, child) => AppScaffoldMessenger(child: child!),
              home: Builder(
                builder: (context) {
                  messageContext = context;
                  return const Scaffold(body: SizedBox.expand());
                },
              ),
            ),
          ),
        );
        final first = showAppSnackBar(
          messageContext,
          content: const Text('First'),
          duration: const Duration(seconds: 1),
        );
        await tester.pumpAndSettle();
        expect(find.text('First'), findsOneWidget);
        final second = showAppSnackBar(
          messageContext,
          content: const Text('Second'),
        );
        await tester.pumpAndSettle();
        expect(await first.closed, SnackBarClosedReason.remove);
        expect(find.text('First'), findsNothing);
        expect(find.text('Second'), findsOneWidget);
        await tester.drag(find.text('Second'), const Offset(0, 300));
        await tester.pumpAndSettle();
        expect(await second.closed, SnackBarClosedReason.swipe);
        expect(find.text('Second'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('rapid messages never leave a backlog or persist an action', (
    tester,
  ) async {
    late BuildContext messageContext;
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => AppScaffoldMessenger(child: child!),
        home: Builder(
          builder: (context) {
            messageContext = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );
    final controllers = [
      for (var i = 0; i < 10; i++)
        ScaffoldMessenger.of(messageContext).showSnackBar(
          SnackBar(
            content: Text('Message $i'),
            action: SnackBarAction(label: 'Action', onPressed: () {}),
            duration: const Duration(minutes: 1),
          ),
        ),
    ];
    await tester.pumpAndSettle();
    expect(find.text('Message 9'), findsOneWidget);
    expect(find.text('Message 0'), findsNothing);
    for (final controller in controllers.take(9)) {
      expect(await controller.closed, SnackBarClosedReason.remove);
    }
    await tester.pump(kAppSnackBarLongestDuration);
    await tester.pumpAndSettle();
    expect(await controllers.last.closed, SnackBarClosedReason.timeout);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('ordinary messages close in 3 s; longer requests keep up to 8 s', () {
    expect(
      appSnackBarDuration(const Duration(seconds: 4)),
      kAppSnackBarDuration,
    );
    expect(
      appSnackBarDuration(const Duration(seconds: 2)),
      const Duration(seconds: 2),
    );
    expect(
      appSnackBarDuration(const Duration(seconds: 6)),
      const Duration(seconds: 6),
    );
    expect(
      appSnackBarDuration(const Duration(seconds: 8)),
      kAppSnackBarLongestDuration,
    );
    expect(
      appSnackBarDuration(const Duration(minutes: 1)),
      kAppSnackBarLongestDuration,
    );
  });

  testWidgets('a 6 s restart hint stays past 3 s', (tester) async {
    late BuildContext messageContext;
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => AppScaffoldMessenger(child: child!),
        home: Builder(
          builder: (context) {
            messageContext = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );
    ScaffoldMessenger.of(messageContext).showSnackBar(
      const SnackBar(content: Text('Restart'), duration: Duration(seconds: 6)),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Restart'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Restart'), findsNothing);
  });
}
