import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/models/theme_settings.dart';
import 'package:mornye/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pins the stored keys, defaults and migrations of the theme settings before
/// any rename. These literals are persisted user data; renaming Dart symbols
/// must never change them.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('every persisted theme key keeps its stored literal', () {
    expect(kThemeModeKey, 'theme_mode');
    expect(kUseDynamicColorKey, 'use_dynamic_color');
    expect(kSeedColorKey, 'seed_color');
    expect(kUseAmoledKey, 'use_amoled');
    expect(kThemeStyleKey, 'theme_style');
    expect(kAccentKey, 'mornye_accent');
    expect(kAccentMovedToBlueKey, 'mornye_accent_moved_to_blue');
    expect(kUseSystemFontKey, 'use_system_font');
    expect(kCustomFontIdKey, 'custom_font_id');
    expect(kCustomFontNameKey, 'custom_font_name');
    expect(kLyricsTextScaleKey, 'lyrics_text_scale');
    expect(kLyricsBlurKey, 'lyrics_blur');
    expect(kLyricsOffsetKey, 'lyrics_offset_ms');
    expect(kGlassOutlinesKey, 'mornye_glass_outlines');
  });

  test('a saved snapshot writes only the retained keys', () {
    final json = const ThemeSettings(
      accent: AppAccent.teal,
      glassOutlines: false,
      lyricsOffsetMs: 250,
    ).toJson();

    expect(json.keys.toSet(), {
      kThemeModeKey,
      kAccentKey,
      kUseSystemFontKey,
      kCustomFontIdKey,
      kCustomFontNameKey,
      kLyricsTextScaleKey,
      kLyricsBlurKey,
      kLyricsOffsetKey,
      kGlassOutlinesKey,
    });
    expect(json[kAccentKey], 'teal');
    expect(json[kGlassOutlinesKey], false);
    expect(json[kLyricsOffsetKey], 250);
  });

  test('a payload from an older install still loads its retained fields', () {
    final settings = ThemeSettings.fromJson({
      kThemeStyleKey: 'material',
      kUseDynamicColorKey: true,
      kSeedColorKey: 0xFF00FF00,
      kUseAmoledKey: true,
      kAccentKey: 'purple',
      kLyricsBlurKey: 0.5,
      kGlassOutlinesKey: false,
    });

    expect(settings.accent, AppAccent.purple);
    expect(settings.lyricsBlur, 0.5);
    expect(settings.glassOutlines, isFalse);
  });

  test(
    'unknown or missing stored values fall back to the retained defaults',
    () {
      final settings = ThemeSettings.fromJson({
        kThemeStyleKey: 'no-such-style',
        kAccentKey: 'magenta',
        kThemeModeKey: 'sideways',
      });

      expect(settings.accent, AppAccent.blue);
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.glassOutlines, isTrue);
      expect(settings.lyricsTextScale, 1);
      expect(settings.lyricsBlur, 1);
      expect(settings.lyricsOffsetMs, 0);
    },
  );

  test('an empty install boots with the retained defaults', () async {
    final prefs = await SharedPreferences.getInstance();
    final settings = loadBootstrapThemeSettings(prefs);

    expect(settings.themeMode, ThemeMode.system);
    expect(settings.accent, AppAccent.blue);
    expect(settings.useSystemFont, isFalse);
    expect(settings.glassOutlines, isTrue);
    expect(settings.lyricsTextScale, 1);
    expect(settings.lyricsBlur, 1);
    expect(settings.lyricsOffsetMs, 0);
  });

  test(
    'the one-time accent move runs once and then keeps a stored red',
    () async {
      SharedPreferences.setMockInitialValues({kAccentKey: 'red'});
      final prefs = await SharedPreferences.getInstance();

      expect(loadBootstrapThemeSettings(prefs).accent, AppAccent.blue);
      expect(prefs.getBool(kAccentMovedToBlueKey), isTrue);

      await prefs.setString(kAccentKey, 'red');
      expect(loadBootstrapThemeSettings(prefs).accent, AppAccent.red);
    },
  );

  test('a stored accent is kept once the move marker is set', () async {
    SharedPreferences.setMockInitialValues({
      kAccentKey: 'red',
      kAccentMovedToBlueKey: true,
    });
    final prefs = await SharedPreferences.getInstance();

    expect(loadBootstrapThemeSettings(prefs).accent, AppAccent.red);
  });

  test('a missing or invalid stored accent loads the blue fallback', () async {
    SharedPreferences.setMockInitialValues({
      kAccentKey: 'not-an-accent',
      kAccentMovedToBlueKey: true,
    });
    final prefs = await SharedPreferences.getInstance();

    expect(loadBootstrapThemeSettings(prefs).accent, AppAccent.blue);
  });

  test(
    'legacy theme style and colour preferences are read without changing',
    () async {
      SharedPreferences.setMockInitialValues({
        kThemeStyleKey: 'material',
        kUseDynamicColorKey: false,
        kSeedColorKey: 0xFFABCDEF,
        kUseAmoledKey: true,
        kAccentKey: 'green',
        kAccentMovedToBlueKey: true,
      });
      final prefs = await SharedPreferences.getInstance();

      final settings = loadBootstrapThemeSettings(prefs);
      expect(settings.accent, AppAccent.green);
      expect(prefs.getString(kThemeStyleKey), 'material');
      expect(prefs.getBool(kUseAmoledKey), isTrue);
    },
  );

  test('the retired glass clarity value is removed once at startup', () async {
    SharedPreferences.setMockInitialValues({'mornye_glass_clarity': 0.4});
    final prefs = await SharedPreferences.getInstance();

    loadBootstrapThemeSettings(prefs);
    await Future<void>.delayed(Duration.zero);
    expect(prefs.containsKey('mornye_glass_clarity'), isFalse);
  });
}
