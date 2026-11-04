import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1455/g1455.dart' show GlassHost, GlassSurface;
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/widgets/glass/debug/app_lyrics_diagnostics.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_surface.dart';

void main() {
  test('each group toggles only its own flag, and normal is all on', () {
    const normal = AppLyricsDiagnostics();
    expect(normal.isNormal, isTrue);
    for (final group in AppLyricsDiagnosticGroup.values) {
      final off = normal.toggled(group);
      expect(off.isNormal, isFalse, reason: group.name);
      expect(off.toggled(group).isNormal, isTrue, reason: group.name);
    }
    expect(normal.toggled(AppLyricsDiagnosticGroup.glass).glass, isFalse);
    expect(normal.toggled(AppLyricsDiagnosticGroup.glass).text, isTrue);
    expect(normal.toggled(AppLyricsDiagnosticGroup.text).motion, isTrue);
  });

  testWidgets(
    'glass group off draws the lyrics glass as Tint, on restores it',
    (tester) async {
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
            home: GlassHost(
              child: const AppLyricsDiagnosticScope(
                child: Scaffold(
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
      expect(find.byType(GlassSurface), findsOneWidget);

      container
          .read(appLyricsDiagnosticsProvider.notifier)
          .toggle(AppLyricsDiagnosticGroup.glass);
      await tester.pumpAndSettle();
      expect(find.byType(GlassSurface), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);

      container
          .read(appLyricsDiagnosticsProvider.notifier)
          .toggle(AppLyricsDiagnosticGroup.glass);
      await tester.pumpAndSettle();
      expect(find.byType(GlassSurface), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a shader mask is built only while masked', (tester) async {
    for (final masked in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          home: AppDiagnosticShaderMask(
            masked: masked,
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Colors.white, Colors.white],
            ).createShader(bounds),
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      );
      expect(
        find.byType(ShaderMask),
        masked ? findsOneWidget : findsNothing,
        reason: 'masked=$masked',
      );
      expect(find.byType(SizedBox), findsWidgets);
    }
  });
}
