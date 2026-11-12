import 'package:flutter/material.dart';

const String kThemeModeKey = 'theme_mode';
const String kUseDynamicColorKey = 'use_dynamic_color';
const String kSeedColorKey = 'seed_color';
const String kUseAmoledKey = 'use_amoled';
// Legacy inputs from the removed alternative design. They are read as inert
// and never written again; old values may remain in preferences.
const String kThemeStyleKey = 'theme_style';
const String kAccentKey = 'mornye_accent';
const String kAccentMovedToBlueKey = 'mornye_accent_moved_to_blue';
const String kUseSystemFontKey = 'use_system_font';
const String kCustomFontIdKey = 'custom_font_id';
const String kCustomFontNameKey = 'custom_font_name';
const String kLyricsTextScaleKey = 'lyrics_text_scale';

double normalizeLyricsTextScale(num? value) =>
    value != null && value.isFinite ? value.toDouble().clamp(0.8, 1.4) : 1.0;
const String kLyricsBlurKey = 'lyrics_blur';

/// How strongly Mornye blurs the lyric lines around the current one: 0 turns
/// it off, 1 is the default.
double normalizeLyricsBlur(num? value) =>
    value != null && value.isFinite ? value.toDouble().clamp(0.0, 1.5) : 1.0;
const String kLyricsOffsetKey = 'lyrics_offset_ms';
const int kMaxLyricsOffsetMs = 2000;

/// How much later synced lyrics follow playback, in milliseconds, so they
/// match audio that reaches the ears late (such as over Bluetooth). Negative
/// values show them earlier.
int normalizeLyricsOffsetMs(num? value) => value != null && value.isFinite
    ? value.round().clamp(-kMaxLyricsOffsetMs, kMaxLyricsOffsetMs)
    : 0;
const String kGlassOutlinesKey = 'mornye_glass_outlines';

enum AppAccent { red, orange, green, teal, blue, purple, pink }

AppAccent appAccentFromString(String? value) => AppAccent.values.firstWhere(
  (accent) => accent.name == value,
  orElse: () => AppAccent.blue,
);

class ThemeSettings {
  final ThemeMode themeMode;
  final AppAccent accent;
  final bool useSystemFont;
  final String customFontId;
  final String customFontName;
  final double lyricsTextScale;
  final double lyricsBlur;
  final int lyricsOffsetMs;
  final bool glassOutlines;

  const ThemeSettings({
    this.themeMode = ThemeMode.system,
    this.accent = AppAccent.blue,
    this.useSystemFont = false,
    this.customFontId = '',
    this.customFontName = '',
    this.lyricsTextScale = 1,
    this.lyricsBlur = 1,
    this.lyricsOffsetMs = 0,
    this.glassOutlines = true,
  });

  ThemeSettings copyWith({
    ThemeMode? themeMode,
    AppAccent? accent,
    bool? useSystemFont,
    String? customFontId,
    String? customFontName,
    double? lyricsTextScale,
    double? lyricsBlur,
    int? lyricsOffsetMs,
    bool? glassOutlines,
  }) {
    return ThemeSettings(
      themeMode: themeMode ?? this.themeMode,
      accent: accent ?? this.accent,
      useSystemFont: useSystemFont ?? this.useSystemFont,
      customFontId: customFontId ?? this.customFontId,
      customFontName: customFontName ?? this.customFontName,
      lyricsTextScale: normalizeLyricsTextScale(
        lyricsTextScale ?? this.lyricsTextScale,
      ),
      lyricsBlur: normalizeLyricsBlur(lyricsBlur ?? this.lyricsBlur),
      lyricsOffsetMs: normalizeLyricsOffsetMs(
        lyricsOffsetMs ?? this.lyricsOffsetMs,
      ),
      glassOutlines: glassOutlines ?? this.glassOutlines,
    );
  }

  Map<String, dynamic> toJson() => {
    kThemeModeKey: themeMode.name,
    kAccentKey: accent.name,
    kUseSystemFontKey: useSystemFont,
    kCustomFontIdKey: customFontId,
    kCustomFontNameKey: customFontName,
    kLyricsTextScaleKey: lyricsTextScale,
    kLyricsBlurKey: lyricsBlur,
    kLyricsOffsetKey: lyricsOffsetMs,
    kGlassOutlinesKey: glassOutlines,
  };

  factory ThemeSettings.fromJson(Map<String, dynamic> json) {
    return ThemeSettings(
      themeMode: themeModeFromString(json[kThemeModeKey] as String?),
      accent: appAccentFromString(json[kAccentKey] as String?),
      useSystemFont: json[kUseSystemFontKey] as bool? ?? false,
      customFontId: json[kCustomFontIdKey] as String? ?? '',
      customFontName: json[kCustomFontNameKey] as String? ?? '',
      lyricsTextScale: normalizeLyricsTextScale(
        json[kLyricsTextScaleKey] as num?,
      ),
      lyricsBlur: normalizeLyricsBlur(json[kLyricsBlurKey] as num?),
      lyricsOffsetMs: normalizeLyricsOffsetMs(json[kLyricsOffsetKey] as num?),
      glassOutlines: json[kGlassOutlinesKey] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThemeSettings &&
        other.themeMode == themeMode &&
        other.accent == accent &&
        other.useSystemFont == useSystemFont &&
        other.customFontId == customFontId &&
        other.customFontName == customFontName &&
        other.lyricsTextScale == lyricsTextScale &&
        other.lyricsBlur == lyricsBlur &&
        other.lyricsOffsetMs == lyricsOffsetMs &&
        other.glassOutlines == glassOutlines;
  }

  @override
  int get hashCode =>
      themeMode.hashCode ^
      accent.hashCode ^
      useSystemFont.hashCode ^
      customFontId.hashCode ^
      customFontName.hashCode ^
      lyricsTextScale.hashCode ^
      lyricsBlur.hashCode ^
      lyricsOffsetMs.hashCode ^
      glassOutlines.hashCode;
}

ThemeMode themeModeFromString(String? value) {
  if (value == null) return ThemeMode.system;
  return ThemeMode.values.firstWhere(
    (e) => e.name == value,
    orElse: () => ThemeMode.system,
  );
}
