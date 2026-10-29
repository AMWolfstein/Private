import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/models/sistrum_glass.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:sistrum/theme/sistrum_glass_levels.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/widgets/glass/sistrum_liquid_backdrop.dart';
import 'package:sistrum/widgets/primitives/app_switch.dart';
import 'package:sistrum/widgets/glass/sistrum_chrome.dart';
import 'package:sistrum/widgets/glass/sistrum_selection_pill.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();

  @override
  void setGlassQuality(SistrumGlassQuality quality) {
    state = state.copyWith(glassQuality: quality.name);
  }
}

SistrumGlassLevel _levelFor({
  required bool lowEnd,
  required SistrumGlassQuality quality,
  required bool liquidCapable,
}) {
  final container = ProviderContainer(
    overrides: [
      lowEndDeviceProvider.overrideWithValue(lowEnd),
      sistrumGlassQualityProvider.overrideWithValue(quality),
      deviceSupportsLiquidGlassProvider.overrideWithValue(liquidCapable),
    ],
  );
  addTearDown(container.dispose);
  return container.read(sistrumGlassLevelProvider);
}

void main() {
  for (final brightness in Brightness.values) {
    for (final reduceMotion in [false, true]) {
      testWidgets(
        'glass override preserves accessibility ($brightness, motion: $reduceMotion)',
        (tester) async {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(
                highContrast: true,
                disableAnimations: reduceMotion,
              );
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                settingsProvider.overrideWith(_Settings.new),
                // A capable GPU must not implicitly override contrast.
                deviceSupportsLiquidGlassProvider.overrideWithValue(true),
                sistrumGlassClarityLevelProvider.overrideWithValue(5),
              ],
              child: MaterialApp(
                theme: SistrumTheme.build(brightness),
                home: Scaffold(
                  body: Column(
                    children: [
                      const SistrumGlass.navigation(
                        blurEnabled: true,
                        child: SizedBox(width: 200, height: 50),
                      ),
                      SistrumSegmentedControl(
                        labels: const ['One', 'Two'],
                        selectedIndex: 0,
                        onChanged: (_) {},
                      ),
                      SistrumTabBar(
                        destinations: const [
                          NavigationDestination(
                            icon: Icon(Icons.home),
                            label: 'Home',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.music_note),
                            label: 'Library',
                          ),
                        ],
                        selectedIndex: 0,
                        onSelected: (_) {},
                        blurEnabled: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          final context = tester.element(find.byType(SistrumTabBar));
          final container = ProviderScope.containerOf(context);
          // Turn the override on and off while the system request stays on.
          for (final forceBlur in [false, true, false]) {
            container
                .read(settingsProvider.notifier)
                .setGlassQuality(
                  forceBlur ? SistrumGlassQuality.full : SistrumGlassQuality.auto,
                );
            await tester.pumpAndSettle();
            // The segmented track sits on the plain page and reads nothing.
            expect(
              find.bySubtype<BackdropFilter>(),
              findsNWidgets(forceBlur ? 2 : 0),
            );
            final pills = tester.widgetList<SistrumSelectionPill>(
              find.byType(SistrumSelectionPill),
            );
            expect(
              pills.every((pill) => pill.contrastBlocked == !forceBlur),
              isTrue,
            );
            expect(pills.last.liquidInteraction, forceBlur && !reduceMotion);
            expect(MediaQuery.highContrastOf(context), isTrue);
            expect(MediaQuery.disableAnimationsOf(context), reduceMotion);
            expect(
              SistrumTabBar.usesLiquidGlass(
                context,
                blurEnabled: true,
                liquidGlass: true,
                contrastBlocked: container.read(
                  sistrumGlassContrastBlockedProvider(true),
                ),
              ),
              forceBlur && !reduceMotion,
            );
          }
          // A live system-contrast change restores normal glass automatically.
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(disableAnimations: reduceMotion);
          await tester.pumpAndSettle();
          expect(find.bySubtype<BackdropFilter>(), findsNWidgets(2));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  test('glass quality picks the level; auto follows the device class', () {
    const auto = SistrumGlassQuality.auto;
    // Low tier: arm32-only or low-RAM Android.
    for (final liquidCapable in [false, true]) {
      expect(
        _levelFor(lowEnd: true, quality: auto, liquidCapable: liquidCapable),
        SistrumGlassLevel.flat,
      );
    }
    // Standard Android: lite glass without shader passes.
    expect(
      _levelFor(lowEnd: false, quality: auto, liquidCapable: false),
      SistrumGlassLevel.lite,
    );
    // High tier (and iOS): full liquid glass.
    expect(
      _levelFor(lowEnd: false, quality: auto, liquidCapable: true),
      SistrumGlassLevel.liquid,
    );
    // An explicit choice applies on every tier.
    for (final lowEnd in [true, false]) {
      for (final liquidCapable in [true, false]) {
        for (final (quality, level) in [
          (SistrumGlassQuality.full, SistrumGlassLevel.liquid),
          (SistrumGlassQuality.lite, SistrumGlassLevel.lite),
          (SistrumGlassQuality.off, SistrumGlassLevel.flat),
        ]) {
          expect(
            _levelFor(
              lowEnd: lowEnd,
              quality: quality,
              liquidCapable: liquidCapable,
            ),
            level,
          );
        }
      }
    }
  });

  test('only auto honours the system contrast request', () {
    for (final quality in SistrumGlassQuality.values) {
      final container = ProviderContainer(
        overrides: [sistrumGlassQualityProvider.overrideWithValue(quality)],
      );
      addTearDown(container.dispose);
      expect(
        container.read(sistrumGlassContrastBlockedProvider(true)),
        quality == SistrumGlassQuality.auto,
      );
      expect(container.read(sistrumGlassContrastBlockedProvider(false)), false);
    }
  });

  testWidgets('frosted level keeps blur but drops every shader surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceSupportsLiquidGlassProvider.overrideWithValue(false),
          sistrumGlassQualityProvider.overrideWithValue(SistrumGlassQuality.auto),
        ],
        child: MaterialApp(
          theme: SistrumTheme.build(Brightness.dark),
          home: Scaffold(
            body: Column(
              children: [
                const SistrumGlass(
                  blurEnabled: true,
                  child: SizedBox(width: 200, height: 50),
                ),
                SistrumSegmentedControl(
                  labels: const ['One', 'Two'],
                  selectedIndex: 0,
                  onChanged: (_) {},
                ),
                AppSwitch(value: true, onChanged: (_) {}),
                Consumer(
                  builder: (context, ref, _) => SistrumTabBar(
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home),
                        label: 'Home',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.music_note),
                        label: 'Library',
                      ),
                    ],
                    selectedIndex: 0,
                    onSelected: (_) {},
                    blurEnabled: ref.watch(sistrumBlurEnabledProvider),
                    liquidGlass: ref.watch(sistrumLiquidGlassProvider),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(SistrumSelectionPill), findsNWidgets(2));
    expect(find.byType(ImageFiltered), findsNothing);
    // The frosted material still samples the page behind it.
    expect(find.bySubtype<BackdropFilter>(), findsWidgets);
    expect(find.text('Library'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each level renders from the table; Level 1 never has a lens', (
    tester,
  ) async {
    Future<void> pumpGlass(int level, SistrumGlassLevel renderer) =>
        tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              sistrumGlassLevelProvider.overrideWithValue(renderer),
              sistrumShaderFiltersSupportedProvider.overrideWithValue(true),
              sistrumGlassClarityLevelProvider.overrideWithValue(level),
            ],
            child: MaterialApp(
              theme: SistrumTheme.build(Brightness.light),
              home: const Center(
                child: SistrumGlass.navigation(
                  blurEnabled: true,
                  child: SizedBox(width: 200, height: 50),
                ),
              ),
            ),
          ),
        );

    Color fill() => tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.color)
        .whereType<Color>()
        .first;

    for (final renderer in [SistrumGlassLevel.lite, SistrumGlassLevel.liquid]) {
      double? lastAlpha;
      for (final spec in kSistrumGlassLevels) {
        await pumpGlass(spec.level, renderer);
        final lens = renderer == SistrumGlassLevel.liquid && !spec.plainBlur;
        final reason = '$renderer level ${spec.level}';
        expect(
          find.byType(LiquidGlassLens),
          lens ? findsOneWidget : findsNothing,
          reason: reason,
        );
        if (lens) {
          final backdrop = tester.widget<SistrumLiquidBackdrop>(
            find.byType(SistrumLiquidBackdrop),
          );
          expect(backdrop.blurSigma, spec.blurSigma, reason: reason);
          expect(backdrop.dispersion, spec.dispersion, reason: reason);
        } else {
          // A plain grouped blur plus the painted lite rim, no shader.
          expect(
            tester
                .widget<BackdropFilter>(find.bySubtype<BackdropFilter>())
                .filter,
            ui.ImageFilter.blur(sigmaX: spec.blurSigma, sigmaY: spec.blurSigma),
            reason: reason,
          );
          expect(find.byType(LiquidGlassLite), findsOneWidget, reason: reason);
          expect(find.byType(SistrumLiquidBackdrop), findsNothing);
        }
        // Clearer levels show more of the page in light mode.
        final alpha = fill().a;
        if (lastAlpha != null) {
          expect(alpha, lessThan(lastAlpha), reason: reason);
        }
        lastAlpha = alpha;
      }
    }
    // The context menu and bar fill read the same table.
    expect(sistrumGlassClarity(0).level, 1);
    expect(sistrumGlassClarity(9).level, 5);
    expect([
      for (final spec in kSistrumGlassLevels) spec.menuOpacity,
    ], orderedEquals([0.74, 0.71, 0.68, 0.62, 0.56]));
  });

  test('blur never drops below sigma 6; clearer levels lighten the tint', () {
    for (final spec in kSistrumGlassLevels) {
      expect(spec.blurSigma, greaterThanOrEqualTo(6), reason: '${spec.level}');
    }
    for (var i = 1; i < kSistrumGlassLevels.length; i++) {
      final (before, after) = (
        kSistrumGlassLevels[i - 1],
        kSistrumGlassLevels[i],
      );
      expect(after.blurSigma, lessThanOrEqualTo(before.blurSigma));
      expect(after.tint, lessThanOrEqualTo(before.tint));
      expect(after.clearFill, greaterThan(before.clearFill));
      expect(after.barFill, lessThan(before.barFill));
    }
  });

  for (final level in [1, 3]) {
    testWidgets('liquid tab and segment pills follow level $level', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sistrumGlassClarityLevelProvider.overrideWithValue(level)],
          child: MaterialApp(
            theme: SistrumTheme.build(Brightness.dark),
            home: Scaffold(
              body: Builder(
                builder: (builderContext) {
                  context = builderContext;
                  return Column(
                    children: [
                      SistrumSegmentedControl(
                        labels: const ['One', 'Two'],
                        selectedIndex: 0,
                        onChanged: (_) {},
                      ),
                      SistrumTabBar(
                        destinations: const [
                          NavigationDestination(
                            icon: Icon(Icons.home),
                            label: 'Home',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.music_note),
                            label: 'Library',
                          ),
                        ],
                        selectedIndex: 0,
                        onSelected: (_) {},
                        blurEnabled: true,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // The floating layout does not depend on the level.
      expect(
        SistrumTabBar.usesLiquidGlass(
          context,
          blurEnabled: true,
          liquidGlass: true,
          contrastBlocked: false,
        ),
        isTrue,
      );
      final pills = tester.widgetList<SistrumSelectionPill>(
        find.byType(SistrumSelectionPill),
      );
      expect(pills, hasLength(2));
      // Held lenses need a level above the plain Level 1 blur.
      expect(pills.every((pill) => pill.liquidInteraction == level >= 2), true);
      // Only the tab bar blurs; the segmented track is tint only.
      expect(find.bySubtype<BackdropFilter>(), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('plain-page panels keep the glass tint without a backdrop pass', (
    tester,
  ) async {
    Color? tintOf(Finder panel) {
      final decorated = tester
          .widgetList<DecoratedBox>(
            find.descendant(of: panel, matching: find.byType(DecoratedBox)),
          )
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((decoration) => decoration.color != null);
      return decorated.color;
    }

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: SistrumTheme.build(Brightness.dark),
          home: const Scaffold(
            body: Column(
              children: [
                SistrumGlass.navigation(
                  key: ValueKey('sampled'),
                  blurEnabled: true,
                  child: SizedBox(width: 200, height: 40),
                ),
                SistrumGlass.navigation(
                  key: ValueKey('plain-page'),
                  blurEnabled: true,
                  samplesBackdrop: false,
                  child: SizedBox(width: 200, height: 40),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final sampled = find.byKey(const ValueKey('sampled'));
    final plain = find.byKey(const ValueKey('plain-page'));
    expect(
      find.descendant(of: sampled, matching: find.bySubtype<BackdropFilter>()),
      findsOneWidget,
    );
    expect(
      find.descendant(of: plain, matching: find.bySubtype<BackdropFilter>()),
      findsNothing,
    );
    // Same translucent material, so the page looks identical behind it.
    expect(tintOf(plain), tintOf(sampled));
    expect(tintOf(plain)!.a, lessThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('full-quality glass has one blur; switches have none', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: SistrumTheme.build(Brightness.dark),
          home: Scaffold(
            body: Column(
              children: [
                const SistrumGlass(
                  blurEnabled: true,
                  child: SizedBox(width: 200, height: 50),
                ),
                AppSwitch(value: true, onChanged: (_) {}),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.bySubtype<BackdropFilter>(), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppSwitch),
        matching: find.bySubtype<BackdropFilter>(),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
