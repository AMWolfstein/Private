import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/widgets/glass/sistrum_chrome.dart';
import 'package:sistrum/widgets/primitives/app_choice_chip.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'search glass sections scroll and filters remain usable in $brightness',
      (tester) async {
        var selected = false;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: SistrumTheme.build(brightness),
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) => Column(
                    children: [
                      SistrumGlassPanel.overlay(
                        radius: 24,
                        child: AppChoiceChip(
                          label: const Text('Albums'),
                          selected: selected,
                          onSelected: (value) =>
                              setState(() => selected = value),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: 12,
                          itemBuilder: (context, index) =>
                              SistrumGlassPanel.overlay(
                                radius: 24,
                                firstInGroup: index == 0,
                                lastInGroup: index == 11,
                                child: Column(
                                  children: [
                                    SizedBox(
                                      height: 88,
                                      child: Text('Result $index'),
                                    ),
                                    if (index < 11)
                                      const Divider(
                                        height: 1,
                                        indent: 80,
                                        endIndent: 12,
                                      ),
                                  ],
                                ),
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Albums'));
        await tester.pumpAndSettle();
        expect(selected, isTrue);
        await tester.scrollUntilVisible(find.text('Result 11'), 200);
        await tester.pumpAndSettle();
        expect(find.text('Result 11').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
