import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/theme/sistrum_theme.dart';

/// Glass lenses and capture views currently mounted.
int glassLenses() =>
    find.byType(LiquidGlassLens).evaluate().length +
    find.byType(LiquidGlassView).evaluate().length;

/// Liquid-glass thumbs currently mounted.
int glassPills() => find.byType(LiquidGlassMotionPill).evaluate().length;

Future<void> pumpGlassControl(
  WidgetTester tester,
  Widget Function(StateSetter setState) builder, {
  bool glass = true,
  bool liquid = true,
  SistrumGlassLevel? level,
  int? clarityLevel,
  bool reduceMotion = false,
  bool highContrast = false,
  TextDirection direction = TextDirection.ltr,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        if (glass)
          sistrumShaderFiltersSupportedProvider.overrideWithValue(true),
        sistrumGlassLevelProvider.overrideWithValue(
          level ?? (liquid ? SistrumGlassLevel.liquid : SistrumGlassLevel.flat),
        ),
        if (clarityLevel != null)
          sistrumGlassClarityLevelProvider.overrideWithValue(clarityLevel),
      ],
      child: MaterialApp(
        theme: SistrumTheme.build(Brightness.light),
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
