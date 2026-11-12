import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mornye/models/theme_settings.dart';
import 'package:mornye/providers/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a stored red moves to blue once, and red picked later stays', () async {
    SharedPreferences.setMockInitialValues({kAccentKey: 'red'});
    final prefs = await SharedPreferences.getInstance();
    expect(loadBootstrapThemeSettings(prefs).accent, AppAccent.blue);
    expect(prefs.getString(kAccentKey), 'blue');

    await prefs.setString(kAccentKey, 'red');
    expect(loadBootstrapThemeSettings(prefs).accent, AppAccent.red);
    expect(prefs.getString(kAccentKey), 'red');
  });

  test('the move leaves any other accent alone', () async {
    SharedPreferences.setMockInitialValues({kAccentKey: 'pink'});
    final prefs = await SharedPreferences.getInstance();
    expect(loadBootstrapThemeSettings(prefs).accent, AppAccent.pink);
    expect(prefs.getString(kAccentKey), 'pink');
    expect(prefs.getBool(kAccentMovedToBlueKey), isTrue);
  });

  test(
    'early theme edits preserve untouched saved settings and await saving',
    () async {
      SharedPreferences.setMockInitialValues({
        kThemeModeKey: 'dark',
        kUseSystemFontKey: true,
        kAccentKey: 'blue',
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
      final savingAccent = notifier.setAccent(AppAccent.red);
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
      expect(state.accent, AppAccent.red);
      expect(state.lyricsTextScale, 1.2);
      expect(state.useSystemFont, isTrue);
      expect(loadBootstrapThemeSettings(prefs), state);
    },
  );

  test('early preview remains immediate without writing preferences', () async {
    SharedPreferences.setMockInitialValues({
      kLyricsTextScaleKey: 0.9,
      kAccentKey: 'blue',
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
      if (next.accent == AppAccent.blue) loaded.complete();
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
          .setLyricsOffsetMs(120);
      releaseLoad.completeError(StateError('theme_load_failed'));
      await saving;
      expect(container.read(themeProvider).lyricsOffsetMs, 120);
    },
  );

  test(
    'disposed theme does not read state or save after delayed loading',
    () async {
      SharedPreferences.setMockInitialValues({kLyricsOffsetKey: 0});
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
          .setLyricsOffsetMs(120);
      container.dispose();
      releaseLoad.complete(prefs);
      await saving;
      expect(prefs.getInt(kLyricsOffsetKey), 0);
    },
  );

  test(
    'the retired glass clarity preference is removed once at startup',
    () async {
      SharedPreferences.setMockInitialValues({'mornye_glass_clarity': 0.4});
      final prefs = await SharedPreferences.getInstance();
      loadBootstrapThemeSettings(prefs);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.containsKey('mornye_glass_clarity'), isFalse);
    },
  );
}
