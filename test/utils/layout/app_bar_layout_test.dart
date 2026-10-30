import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/utils/layout/app_bar_layout.dart';

void main() {
  for (final (padding, expected) in [(0.0, 0.0), (10.0, 10.0), (59.0, 24.0)]) {
    testWidgets('a $padding dp status bar gives $expected dp header padding', (
      tester,
    ) async {
      late double result;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(padding: EdgeInsets.only(top: padding)),
          child: Builder(
            builder: (context) {
              result = normalizedHeaderTopPadding(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(result, expected);
    });
  }

  testWidgets('a caller can lower the cap below the default', (tester) async {
    late double result;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(top: 59)),
        child: Builder(
          builder: (context) {
            result = normalizedHeaderTopPadding(context, max: 12);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(result, 12);
  });
}
