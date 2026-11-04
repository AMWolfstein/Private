import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1455/g1455.dart' show GlassHost, GlassSurface;
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/widgets/glass/debug/app_liquid_diagnostic.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_surface.dart';

void main() {
  testWidgets('the HUD switch draws LIQUID as TINT, and only LIQUID', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        appGlassLevelProvider.overrideWithValue(AppGlassLevel.tinted),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark),
          home: const GlassHost(
            child: Scaffold(
              body: Column(
                children: [
                  AppGlass(
                    blurEnabled: true,
                    mode: AppGlassMode.liquid,
                    child: SizedBox(width: 120, height: 48),
                  ),
                  AppGlass(
                    blurEnabled: true,
                    mode: AppGlassMode.frosted,
                    child: SizedBox(width: 120, height: 48),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(GlassSurface), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);

    container.read(appLiquidDiagnosticProvider.notifier).toggle();
    await tester.pumpAndSettle();
    // No LIQUID surface is mounted, so the host has nothing to capture for.
    expect(find.byType(GlassSurface), findsNothing);
    expect(find.byType(BackdropFilter), findsOneWidget);

    container.read(appLiquidDiagnosticProvider.notifier).toggle();
    await tester.pumpAndSettle();
    expect(find.byType(GlassSurface), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
