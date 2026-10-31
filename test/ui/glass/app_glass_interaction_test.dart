import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/primitives/app_switch.dart';
import 'package:sistrum/widgets/glass/chrome/app_chrome.dart';
import 'package:sistrum/widgets/glass/chrome/app_chrome_controls.dart';
import 'package:sistrum/widgets/glass/selection/app_selection_pill.dart';
import 'package:sistrum/widgets/glass/selection/app_selection_foreground.dart';

part 'app_glass_interaction_1.dart';

void _maskCullingTests() {
  for (final direction in TextDirection.values) {
    testWidgets(
      'selection masks cull and restore retained layers ($direction)',
      (tester) async {
        var selected = 0;
        Color color = Colors.red;
        late StateSetter update;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Directionality(
                textDirection: direction,
                child: Center(
                  child: SizedBox(
                    width: 300,
                    height: 64,
                    child: StatefulBuilder(
                      builder: (_, setState) {
                        update = setState;
                        return AppSelectionPill(
                          labels: const ['A', 'B', 'C', 'D', 'E'],
                          selectedIndex: selected,
                          selectionColor: color,
                          maskItemForeground: false,
                          padding: EdgeInsets.zero,
                          onChanged: (_) {},
                          itemBuilder: (_, _, _) => const Center(
                            child: AppSelectionForeground(
                              child: SizedBox(
                                width: 16,
                                height: 40,
                                child: ColoredBox(color: Colors.white),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => ui.FragmentProgram.fromAsset(
            'assets/shaders/app_selection_mask.frag',
          ),
        );
        await tester.pumpAndSettle();
        final masks = tester
            .renderObjectList<RenderShaderMask>(
              find.byWidgetPredicate((widget) => widget is ShaderMask),
            )
            .toList();
        int activeMasks() => masks.where((mask) => mask.layer != null).length;
        expect(masks, hasLength(5));
        expect(activeMasks(), 1);
        expect(masks.first.layer, isNotNull);

        update(() => selected = 4);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 110));
        expect(activeMasks(), inInclusiveRange(1, 2));
        await tester.pumpAndSettle();
        expect(activeMasks(), 1);
        expect(masks.first.layer, isNull);
        expect(masks.last.layer, isNotNull);

        update(() => color = Colors.transparent);
        await tester.pumpAndSettle();
        expect(activeMasks(), 0);
        update(() => color = Colors.red);
        await tester.pumpAndSettle();
        expect(activeMasks(), 1);
        expect(masks.last.layer, isNotNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('selection culling includes overflowing child paint bounds', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 64,
              child: AppSelectionPill(
                labels: const ['A', 'B', 'C', 'D', 'E'],
                selectedIndex: 0,
                selectionColor: Colors.red,
                maskItemForeground: false,
                padding: EdgeInsets.zero,
                onChanged: (_) {},
                itemBuilder: (_, index, _) => Center(
                  child: AppSelectionForeground(
                    child: index == 4
                        ? const _OverflowForeground()
                        : const SizedBox(
                            width: 16,
                            height: 40,
                            child: ColoredBox(color: Colors.white),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => ui.FragmentProgram.fromAsset(
        'assets/shaders/app_selection_mask.frag',
      ),
    );
    await tester.pumpAndSettle();
    final masks = tester
        .renderObjectList<RenderShaderMask>(
          find.byWidgetPredicate((widget) => widget is ShaderMask),
        )
        .toList();
    expect(masks.last.child!.paintBounds.left, lessThan(0));
    expect(masks.last.layer, isNotNull);
    expect(masks.where((mask) => mask.layer != null), hasLength(2));
    expect(tester.takeException(), isNull);
  });
}

void main() {
  _registerAppGlassInteraction1();
}

class _OverflowForeground extends LeafRenderObjectWidget {
  const _OverflowForeground();

  @override
  RenderBox createRenderObject(BuildContext context) =>
      _RenderOverflowForeground();
}

class _RenderOverflowForeground extends RenderBox {
  @override
  void performLayout() => size = constraints.constrain(const Size(16, 40));

  @override
  Rect get paintBounds => Rect.fromLTRB(-280, 0, size.width, size.height);

  @override
  void paint(PaintingContext context, Offset offset) => context.canvas.drawRect(
    paintBounds.shift(offset),
    Paint()..color = Colors.white,
  );
}

Future<List<int>> _foregroundPixels(
  WidgetTester tester,
  GlobalKey capture,
  Finder finder,
  List<Color> colors,
) async {
  final boundary =
      capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final rect = tester
      .getRect(finder)
      .shift(-boundary.localToGlobal(Offset.zero));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData())!;
      final counts = List.filled(colors.length, 0);
      for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
        for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
          final offset = (y * image.width + x) * 4;
          for (var i = 0; i < colors.length; i++) {
            final argb = colors[i].toARGB32();
            if ((bytes.getUint8(offset) - ((argb >> 16) & 255)).abs() <= 2 &&
                (bytes.getUint8(offset + 1) - ((argb >> 8) & 255)).abs() <= 2 &&
                (bytes.getUint8(offset + 2) - (argb & 255)).abs() <= 2) {
              counts[i]++;
            }
          }
        }
      }
      return counts;
    } finally {
      image.dispose();
    }
  }))!;
}
