import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/models/theme_settings.dart';
import 'package:sistrum/providers/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'theme settings round-trip through json and bootstrap preferences',
    () async {
      final values = <String, Object>{
        kAppAccentKey: 'green',
        kAppGlassOutlinesKey: false,
      };
      final restored = ThemeSettings.fromJson(values);
      expect(restored.appAccent, AppAccent.green);
      expect(restored.appGlassOutlines, isFalse);
      expect(restored.toJson()[kAppAccentKey], 'green');
      expect(restored.toJson()[kAppGlassOutlinesKey], isFalse);

      SharedPreferences.setMockInitialValues(values);
      final prefs = await SharedPreferences.getInstance();
      expect(loadBootstrapThemeSettings(prefs), restored);
      final container = ProviderContainer(
        overrides: [
          themeProvider.overrideWith(
            () => ThemeNotifier(preferences: Future.value(prefs)),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(themeProvider.notifier).setLyricsTextScale(1.1);
      expect(
        container.read(themeProvider).appAccent,
        restored.appAccent,
      );
      expect(prefs.getString(kAppAccentKey), 'green');
      expect(prefs.getBool(kAppGlassOutlinesKey), isFalse);
    },
  );

  test(
    'early theme edits preserve untouched saved settings and await saving',
    () async {
      SharedPreferences.setMockInitialValues({
        kThemeModeKey: 'dark',
        'theme_style': 'sistrum',
        'seed_color': 0xff123456,
        'use_dynamic_color': false,
        'use_amoled': true,
        kUseSystemFontKey: true,
        kAppAccentKey: 'blue',
        kPlayerViewKey: 'immersive',
        kLyricsTextScaleKey: 0.9,
      });
      final prefs = await SharedPreferences.getInstance();
      final releaseLoad = Completer<SharedPreferences>();
      final container = ProviderContainer(
        overrides: [
          themeProvider.overrideWith(
            () => ThemeNotifier(preferences: releaseLoad.future),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(themeProvider.notifier);
      // An explicit edit equal to the bootstrap default still owns this field.
      final savingMode = notifier.setThemeMode(ThemeMode.system);
      final savingAccent = notifier.setAppAccent(AppAccent.red);
      await notifier.setLyricsTextScale(1.2, persist: false);
      var saved = false;
      unawaited(savingAccent.then((_) => saved = true));
      await Future<void>.delayed(Duration.zero);
      expect(saved, isFalse);
      expect(container.read(themeProvider).lyricsTextScale, 1.2);
      expect(prefs.getString(kThemeModeKey), 'dark');

      releaseLoad.complete(prefs);
      await Future.wait([savingMode, savingAccent]);
      final state = container.read(themeProvider);
      expect(state.themeMode, ThemeMode.system);
      expect(state.appAccent, AppAccent.red);
      expect(state.lyricsTextScale, 1.2);
      expect(state.playerView, PlayerView.immersive);
      expect(state.useSystemFont, isTrue);
      expect(loadBootstrapThemeSettings(prefs), state);
    },
  );

  test('early preview remains immediate without writing preferences', () async {
    SharedPreferences.setMockInitialValues({
      kLyricsTextScaleKey: 0.9,
      kAppAccentKey: 'blue',
    });
    final prefs = await SharedPreferences.getInstance();
    final releaseLoad = Completer<SharedPreferences>();
    final loaded = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        themeProvider.overrideWith(
          () => ThemeNotifier(preferences: releaseLoad.future),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(themeProvider, (_, next) {
      if (next.appAccent == AppAccent.blue) loaded.complete();
    });
    await container
        .read(themeProvider.notifier)
        .setLyricsTextScale(1.2, persist: false);
    expect(container.read(themeProvider).lyricsTextScale, 1.2);
    releaseLoad.complete(prefs);
    await loaded.future;
    expect(container.read(themeProvider).lyricsTextScale, 1.2);
    expect(prefs.getDouble(kLyricsTextScaleKey), 0.9);
  });

  test(
    'failed preference loading keeps early edits without leaking errors',
    () async {
      final releaseLoad = Completer<SharedPreferences>();
      final container = ProviderContainer(
        overrides: [
          themeProvider.overrideWith(
            () => ThemeNotifier(preferences: releaseLoad.future),
          ),
        ],
      );
      addTearDown(container.dispose);
      final saving = container
          .read(themeProvider.notifier)
          .setUseSystemFont(true);
      releaseLoad.completeError(StateError('theme_load_failed'));
      await saving;
      expect(container.read(themeProvider).useSystemFont, isTrue);
    },
  );

  test(
    'disposed theme does not read state or save after delayed loading',
    () async {
      SharedPreferences.setMockInitialValues({kUseSystemFontKey: false});
      final prefs = await SharedPreferences.getInstance();
      final releaseLoad = Completer<SharedPreferences>();
      final container = ProviderContainer(
        overrides: [
          themeProvider.overrideWith(
            () => ThemeNotifier(preferences: releaseLoad.future),
          ),
        ],
      );
      final saving = container
          .read(themeProvider.notifier)
          .setUseSystemFont(true);
      container.dispose();
      releaseLoad.complete(prefs);
      await saving;
      expect(prefs.getBool(kUseSystemFontKey), isFalse);
    },
  );
}
