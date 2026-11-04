import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/widgets/glass/artwork/app_artwork_glass.dart';
import 'package:sistrum/widgets/glass/artwork/app_screen_ground.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';

Future<void> _pump(WidgetTester tester, AppGlassLevel level) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [appGlassLevelProvider.overrideWithValue(level)],
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark),
          builder: (context, child) => AppScreenCapture(child: child!),
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  for (var i = 0; i < 4; i++)
                    Container(height: 80, color: Colors.primaries[i]),
                  TextButton(
                    onPressed: () => showAppScrollableBottomSheet<void>(
                      context: context,
                      title: 'Sheet',
                      builder: (context, controller) => ListView(
                        controller: controller,
                        children: const [Text('row')],
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

Finder _sheetGlass(Type type) => find.descendant(
  of: find.byType(BottomSheet),
  matching: find.byType(type),
);

void main() {
  testWidgets('a sheet draws the screen captured once, not a live read', (
    tester,
  ) async {
    await _pump(tester, AppGlassLevel.tinted);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('row'), findsOneWidget);
    expect(_sheetGlass(AppArtworkGlassSurface), findsOneWidget);
    expect(_sheetGlass(BackdropFilter), findsNothing);

    // Closing the sheet releases its ground without errors.
    Navigator.of(tester.element(find.text('row'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('row'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('flat glass captures nothing', (tester) async {
    await _pump(tester, AppGlassLevel.flat);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('row'), findsOneWidget);
    expect(_sheetGlass(AppArtworkGlassSurface), findsNothing);
    expect(_sheetGlass(BackdropFilter), findsNothing);
  });

  testWidgets('without the capture boundary a sheet keeps its live read', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appGlassLevelProvider.overrideWithValue(AppGlassLevel.tinted),
        ],
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppScrollableBottomSheet<void>(
                  context: context,
                  title: 'Sheet',
                  builder: (context, controller) => ListView(
                    controller: controller,
                    children: const [Text('row')],
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(_sheetGlass(AppArtworkGlassSurface), findsNothing);
    expect(_sheetGlass(BackdropFilter), findsOneWidget);
  });
}
