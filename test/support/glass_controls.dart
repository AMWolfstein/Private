import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_thumb.dart';

/// Whether [element] is painted: no ancestor [AnimatedOpacity] sits at zero.
bool _painted(Element element) {
  final fade = element.findAncestorWidgetOfExactType<AnimatedOpacity>();
  return fade == null || fade.opacity > 0;
}

/// Backdrop blurs currently painted: each one is a glass surface's read.
int glassBlurs() =>
    find.byType(BackdropFilter).evaluate().where(_painted).length;

/// Held thumb glass currently painted (a touched switch or slider).
int glassPills() =>
    find.byKey(kAppGlassThumbKey).evaluate().where(_painted).length;

Future<void> pumpGlassControl(
  WidgetTester tester,
  Widget Function(StateSetter setState) builder, {
  bool glass = true,
  AppGlassLevel? level,
  bool reduceMotion = false,
  bool highContrast = false,
  TextDirection direction = TextDirection.ltr,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        appGlassLevelProvider.overrideWithValue(
          level ?? (glass ? AppGlassLevel.tinted : AppGlassLevel.flat),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(
            disableAnimations: reduceMotion,
            highContrast: highContrast,
          ),
          child: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  child: StatefulBuilder(
                    builder: (context, setState) => builder(setState),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
