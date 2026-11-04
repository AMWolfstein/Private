import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1455/g1455.dart' show GlassHost, GlassSurface;
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_surface.dart';

Future<void> _pump(WidgetTester tester, {required bool liveVideo}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appGlassLevelProvider.overrideWithValue(AppGlassLevel.tinted),
      ],
      child: MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        home: GlassHost(
          child: AppLiveVideoBackdrop(
            live: liveVideo,
            child: const Scaffold(
              body: Center(
                child: AppGlass(
                  blurEnabled: true,
                  mode: AppGlassMode.liquid,
                  child: SizedBox(width: 120, height: 80),
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

void main() {
  testWidgets('LIQUID over a live video reads the live backdrop (FROSTED)', (
    tester,
  ) async {
    await _pump(tester, liveVideo: true);
    expect(find.byType(GlassSurface), findsNothing);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LIQUID without a live video keeps its refraction', (
    tester,
  ) async {
    await _pump(tester, liveVideo: false);
    expect(find.byType(GlassSurface), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
