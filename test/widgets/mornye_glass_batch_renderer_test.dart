import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:mornye/models/settings.dart';
import 'package:mornye/providers/runtime_profile_provider.dart';
import 'package:mornye/providers/settings_provider.dart';
import 'package:mornye/theme/mornye_theme.dart';
import 'package:mornye/widgets/mornye_chrome.dart';
import 'package:mornye/widgets/mornye_liquid_backdrop.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.renderer);
  final String renderer;

  @override
  AppSettings build() => AppSettings(glassBatchRenderer: renderer);
}

void main() {
  setUp(() => MornyeGlassRules.debugShaderFilterSupport = true);
  tearDown(() => MornyeGlassRules.debugShaderFilterSupport = null);

  test('unknown or missing values keep the reviewed default', () {
    expect(
      MornyeGlassBatchRenderer.fromWire('separate_pass'),
      MornyeGlassBatchRenderer.separatePass,
    );
    expect(
      MornyeGlassBatchRenderer.fromWire('bogus'),
      MornyeGlassBatchRenderer.separatePass,
    );
    expect(
      MornyeGlassBatchRenderer.fromWire(''),
      MornyeGlassBatchRenderer.separatePass,
    );
  });

  test('each option maps to its 5.2.0 batch mode and blur method', () {
    final separate = MornyeGlassBatchRenderer.separatePass;
    expect(separate.mode, LiquidGlassBatchMode.separatePass);
    expect(separate.blurMethod, LiquidGlassBlurMethod.engine);

    final single = MornyeGlassBatchRenderer.fromWire('single_pass');
    expect(single, MornyeGlassBatchRenderer.singlePass);
    expect(single.mode, LiquidGlassBatchMode.singlePass);
    expect(single.blurMethod, LiquidGlassBlurMethod.engine);

    final shader = MornyeGlassBatchRenderer.fromWire('shader_blur');
    expect(shader, MornyeGlassBatchRenderer.shader);
    expect(shader.blurMethod, LiquidGlassBlurMethod.shader);
  });

  for (final wire in ['separate_pass', 'single_pass', 'shader_blur']) {
    testWidgets('a batched Mornye lens takes the selected renderer ($wire)', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(() => _Settings(wire)),
            deviceSupportsBackdropBlurProvider.overrideWithValue(true),
            deviceSupportsLiquidGlassProvider.overrideWithValue(true),
          ],
          child: MaterialApp(
            theme: MornyeTheme.build(Brightness.light, glassClarity: 0.75),
            home: const Scaffold(
              body: MornyeGlass.navigation(
                blurEnabled: true,
                child: SizedBox(width: 200, height: 50),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final expected = MornyeGlassBatchRenderer.fromWire(wire);
      final batch = tester.widget<LiquidGlassBatch>(
        find.byType(LiquidGlassBatch).first,
      );
      expect(batch.mode, expected.mode);
      expect(batch.blurMethod, expected.blurMethod);
    });
  }
}
