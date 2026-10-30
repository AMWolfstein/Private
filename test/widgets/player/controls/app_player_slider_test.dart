import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/player/controls/app_player_slider.dart';

void main() {
  testWidgets('drag reports changes with start and end gestures', (
    tester,
  ) async {
    final changes = <double>[];
    final starts = <double>[];
    final ends = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: AppPlayerSlider(
                value: 0,
                max: 10,
                onChanged: changes.add,
                onChangeStart: starts.add,
                onChangeEnd: ends.add,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(Slider), const Offset(120, 0));
    await tester.pumpAndSettle();

    expect(starts, hasLength(1));
    expect(changes, isNotEmpty);
    expect(changes.last, greaterThan(0));
    expect(changes.last, lessThanOrEqualTo(10));
    expect(ends, hasLength(1));
  });

  testWidgets('shows the given value, range and colours on the slider', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: AppPlayerSlider(
              value: 4,
              max: 8,
              activeColor: Colors.amber,
              inactiveColor: Colors.blueGrey,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 4);
    expect(slider.max, 8);
    expect(slider.activeColor, Colors.amber);
    expect(slider.inactiveColor, Colors.blueGrey);
    expect(tester.getSize(find.byType(AppPlayerSlider)).height, 44);
  });
}
