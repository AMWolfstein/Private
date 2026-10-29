import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/glass/app_artwork_ground.dart';
import 'package:sistrum/widgets/glass/app_artwork_page_ground.dart';

/// PERF-605: collapsing the artist header shrinks the ground anchor's box on
/// every frame. The page ground must be built once for the expanded size and
/// never rebuilt while the header collapses.
void main() {
  testWidgets('collapse frames do not rebuild the page ground', (tester) async {
    double currentExtent = 200;
    double width = 300;
    Widget buildPage() {
      return MaterialApp(
        home: Scaffold(
          body: AppPageGround(
            source: '/cover.jpg',
            surface: Colors.black,
            sigma: 6,
            enabled: true,
            cover: null,
            child: FlexibleSpaceBarSettings(
              key: const ValueKey('settings'),
              toolbarOpacity: 1,
              minExtent: 100,
              maxExtent: 200,
              currentExtent: currentExtent,
              child: AppGroundAnchor(
                layout: const AppGroundLayout(
                  stops: [0, 0.5, 1],
                  colors: [Colors.black, Colors.black26, Colors.black],
                ),
                child: SizedBox(
                  width: width,
                  height: currentExtent,
                ),
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();
    // The expanded ground is built exactly once (async build settles within
    // the first pumpAndSettle).
    final expandedBuilds = AppGroundBuilder.debugBuildCount;
    expect(expandedBuilds, 1);

    AppGroundBuilder.debugBuildCount = 0;
    for (currentExtent = 195; currentExtent >= 100; currentExtent -= 5) {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
    }
    expect(AppGroundBuilder.debugBuildCount, 0);

    // Widening the page still rebuilds the ground at the new width.
    currentExtent = 120;
    width = 360;
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();
    expect(AppGroundBuilder.debugBuildCount, 1);
  });
}
