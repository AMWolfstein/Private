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
    expect(kMornyeAccentKey, 'mornye_accent');
    expect(kMornyeAccentMovedToBlueKey, 'mornye_accent_moved_to_blue');
    expect(kUseSystemFontKey, 'use_system_font');
    expect(kCustomFontIdKey, 'custom_font_id');
    expect(kCustomFontNameKey, 'custom_font_name');
    expect(kLyricsTextScaleKey, 'lyrics_text_scale');
    expect(kLyricsBlurKey, 'lyrics_blur');
    expect(kLyricsOffsetKey, 'lyrics_offset_ms');
    expect(kMornyeGlassOutlinesKey, 'mornye_glass_outlines');
  });

  test('a saved snapshot writes exactly the retained keys', () {
    final json = const ThemeSettings(
      mornyeAccent: MornyeAccent.teal,
      mornyeGlassOutlines: false,
      lyricsOffsetMs: 250,
    ).toJson();

    expect(
      json.keys.toSet(),
      {
        kThemeModeKey,
        kUseDynamicColorKey,
        kSeedColorKey,
        kUseAmoledKey,
        kThemeStyleKey,
        kMornyeAccentKey,
        kUseSystemFontKey,
        kCustomFontIdKey,
        kCustomFontNameKey,
        kLyricsTextScaleKey,
        kLyricsBlurKey,
        kLyricsOffsetKey,
        kMornyeGlassOutlinesKey,
      },
    );
    expect(json[kMornyeAccentKey], 'teal');
    expect(json[kMornyeGlassOutlinesKey], false);
    expect(json[kLyricsOffsetKey], 250);
  });

  test('a payload from an older install still loads its retained fields', () {
    final settings = ThemeSettings.fromJson({
      kThemeStyleKey: 'material',
      kUseDynamicColorKey: true,
      kSeedColorKey: 0xFF00FF00,
      kUseAmoledKey: true,
      kMornyeAccentKey: 'purple',
      kLyricsBlurKey: 0.5,
      kMornyeGlassOutlinesKey: false,
    });

    expect(settings.mornyeAccent, MornyeAccent.purple);
    expect(settings.lyricsBlur, 0.5);
    expect(settings.mornyeGlassOutlines, isFalse);
  });

  test('unknown or missing stored values fall back to the retained defaults', () {
    final settings = ThemeSettings.fromJson({
      kThemeStyleKey: 'no-such-style',
      kMornyeAccentKey: 'magenta',
      kThemeModeKey: 'sideways',
    });

    expect(settings.mornyeAccent, MornyeAccent.blue);
    expect(settings.themeMode, ThemeMode.system);
    expect(settings.mornyeGlassOutlines, isTrue);
    expect(settings.lyricsTextScale, 1);
    expect(settings.lyricsBlur, 1);
    expect(settings.lyricsOffsetMs, 0);
  });

  test('an empty install boots with the retained defaults', () async {
    final prefs = await SharedPreferences.getInstance();
    final settings = loadBootstrapThemeSettings(prefs);

    expect(settings.themeMode, ThemeMode.system);
    expect(settings.mornyeAccent, MornyeAccent.blue);
    expect(settings.useSystemFont, isFalse);
    expect(settings.mornyeGlassOutlines, isTrue);
    expect(settings.lyricsTextScale, 1);
    expect(settings.lyricsBlur, 1);
    expect(settings.lyricsOffsetMs, 0);
  });

  test('the one-time accent move runs once and then keeps a stored red', () async {
    SharedPreferences.setMockInitialValues({kMornyeAccentKey: 'red'});
    final prefs = await SharedPreferences.getInstance();

    expect(loadBootstrapThemeSettings(prefs).mornyeAccent, MornyeAccent.blue);
    expect(prefs.getBool(kMornyeAccentMovedToBlueKey), isTrue);

    await prefs.setString(kMornyeAccentKey, 'red');
    expect(loadBootstrapThemeSettings(prefs).mornyeAccent, MornyeAccent.red);
  });

  test('a stored accent is kept once the move marker is set', () async {
    SharedPreferences.setMockInitialValues({
      kMornyeAccentKey: 'red',
      kMornyeAccentMovedToBlueKey: true,
    });
    final prefs = await SharedPreferences.getInstance();

    expect(loadBootstrapThemeSettings(prefs).mornyeAccent, MornyeAccent.red);
  });

  test('a missing or invalid stored accent loads the blue fallback', () async {
    SharedPreferences.setMockInitialValues({
      kMornyeAccentKey: 'not-an-accent',
      kMornyeAccentMovedToBlueKey: true,
    });
    final prefs = await SharedPreferences.getInstance();

    expect(loadBootstrapThemeSettings(prefs).mornyeAccent, MornyeAccent.blue);
  });

  test('legacy theme style and colour preferences are read without changing', () async {
    SharedPreferences.setMockInitialValues({
      kThemeStyleKey: 'material',
      kUseDynamicColorKey: false,
      kSeedColorKey: 0xFFABCDEF,
      kUseAmoledKey: true,
      kMornyeAccentKey: 'green',
      kMornyeAccentMovedToBlueKey: true,
    });
    final prefs = await SharedPreferences.getInstance();

    final settings = loadBootstrapThemeSettings(prefs);
    expect(settings.mornyeAccent, MornyeAccent.green);
    expect(prefs.getString(kThemeStyleKey), 'material');
    expect(prefs.getBool(kUseAmoledKey), isTrue);
  });

  test('the retired glass clarity value is removed once at startup', () async {
    SharedPreferences.setMockInitialValues({'mornye_glass_clarity': 0.4});
    final prefs = await SharedPreferences.getInstance();

    loadBootstrapThemeSettings(prefs);
    await Future<void>.delayed(Duration.zero);
    expect(prefs.containsKey('mornye_glass_clarity'), isFalse);
  });
}
