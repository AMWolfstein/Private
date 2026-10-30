import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/status/beta_badge.dart';

void main() {
  testWidgets('the badge labels a feature as beta', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: BetaBadge())),
      ),
    );
    expect(find.text('Beta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
