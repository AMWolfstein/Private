import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/player/layout/app_player_header_layout.dart';

Widget _layout({
  required double progress,
  bool expandLyrics = false,
  bool withOptions = false,
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 400,
      height: 400,
      child: CustomMultiChildLayout(
        delegate: AppPlayerHeaderLayout(
          progress: progress,
          compactHeight: 56,
          compactLeft: 16,
          expandLyrics: expandLyrics,
        ),
        children: [
          LayoutId(
            id: AppPlayerHeaderSlot.stage,
            child: const SizedBox.shrink(),
          ),
          LayoutId(
            id: AppPlayerHeaderSlot.header,
            child: const SizedBox(height: 50, child: Text('Header')),
          ),
          LayoutId(
            id: AppPlayerHeaderSlot.controls,
            child: const SizedBox(height: 40, child: Text('Controls')),
          ),
          if (withOptions)
            LayoutId(
              id: AppPlayerHeaderSlot.lyricsOptions,
              child: const SizedBox(height: 30, child: Text('Options')),
            ),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('the controls sit at the bottom of the player', (tester) async {
    await tester.pumpWidget(_layout(progress: 0));
    final controls = tester.getRect(find.text('Controls'));
    expect(controls.bottom, closeTo(400, 0.5));
    expect(controls.height, 40);
  });

  testWidgets('the header is full width at rest and compact when collapsed', (
    tester,
  ) async {
    await tester.pumpWidget(_layout(progress: 0));
    final rest = tester.getRect(find.text('Header'));
    expect(rest.left, 28);

    await tester.pumpWidget(_layout(progress: 1));
    final compact = tester.getRect(find.text('Header'));
    expect(compact.left, 16);
    expect(compact.top, 8);
  });

  testWidgets('lyrics options sit above the controls when present', (
    tester,
  ) async {
    await tester.pumpWidget(_layout(progress: 0, withOptions: true));
    final options = tester.getRect(find.text('Options'));
    final controls = tester.getRect(find.text('Controls'));
    expect(options.bottom, lessThanOrEqualTo(controls.top));
  });
}
