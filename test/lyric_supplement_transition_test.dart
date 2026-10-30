import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/lyrics/lyric_supplement_transition.dart';

void main() {
  testWidgets('a hidden supplement takes no height and is transparent', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LyricSupplementTransition(
              visibility: 0,
              child: SizedBox(height: 40, width: 100),
            ),
          ],
        ),
      ),
    );
    expect(tester.getSize(find.byType(LyricSupplementTransition)).height, 0);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);
  });

  testWidgets('a shown supplement keeps its full height and opacity', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LyricSupplementTransition(
              visibility: 1,
              child: SizedBox(height: 40, width: 100),
            ),
          ],
        ),
      ),
    );
    expect(tester.getSize(find.byType(LyricSupplementTransition)).height, 40);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
  });

  testWidgets('a backing line is clipped until it has fully opened', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: LyricBackingTransition(
          visibility: 0.5,
          child: SizedBox(height: 40, width: 100),
        ),
      ),
    );
    expect(
      tester.widget<ClipRect>(find.byType(ClipRect)).clipBehavior,
      Clip.hardEdge,
    );

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: LyricBackingTransition(
          visibility: 1,
          child: SizedBox(height: 40, width: 100),
        ),
      ),
    );
    expect(
      tester.widget<ClipRect>(find.byType(ClipRect)).clipBehavior,
      Clip.none,
    );
  });
}
