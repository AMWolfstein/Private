import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/screens/setup_step_layout.dart';

void main() {
  testWidgets('a setup step shows its icon, title, description and action', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SetupStepLayout(
            title: 'Pick a folder',
            description: 'Choose where your music lives',
            icon: Icons.folder,
            child: Text('Action'),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.folder), findsOneWidget);
    expect(find.text('Pick a folder'), findsOneWidget);
    expect(find.text('Choose where your music lives'), findsOneWidget);
    expect(find.text('Action'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a success card shows its text with a check mark', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SetupSuccessCard(
            text: 'Library scanned',
            colorScheme: ColorScheme.light(),
          ),
        ),
      ),
    );
    expect(find.text('Library scanned'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  test('the header height constant matches the step header layout', () {
    expect(kSetupHeaderHeight, 80);
  });
}
