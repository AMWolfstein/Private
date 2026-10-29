import 'package:flutter/material.dart';

const String kThemeModeKey = 'theme_mode';
const String kAppAccentKey = 'sistrum_accent';
const String kUseSystemFontKey = 'use_system_font';
const String kCustomFontIdKey = 'custom_font_id';
const String kCustomFontNameKey = 'custom_font_name';
const String kPlayerViewKey = 'player_view';
const String kLyricsTextScaleKey = 'lyrics_text_scale';

double normalizeLyricsTextScale(num? value) =>
    value != null && value.isFinite ? value.toDouble().clamp(0.8, 1.4) : 1.0;
const String kAppGlassOutlinesKey = 'sistrum_glass_outlines';

enum PlayerView { normal, immersive }

PlayerView playerViewFromString(String? value) => PlayerView.values.firstWhere(
  (view) => view.name == value,
  orElse: () => PlayerView.normal,
);

enum AppAccent { red, orange, green, teal, blue, purple, pink }

AppAccent appAccentFromString(String? value) =>
    AppAccent.values.firstWhere(
      (accent) => accent.name == value,
      orElse: () => AppAccent.red,
    );

class ThemeSettings {
  final ThemeMode themeMode;
  final PlayerView playerView;

  final AppAccent appAccent;
  final bool useSystemFont;
  final String customFontId;
  final String customFontName;
  final double lyricsTextScale;
  final bool appGlassOutlines;

  const ThemeSettings({
    this.themeMode = ThemeMode.system,
    this.playerView = PlayerView.normal,

    this.appAccent = AppAccent.red,
    this.useSystemFont = false,
    this.customFontId = '',
    this.customFontName = '',
    this.lyricsTextScale = 1,
    this.appGlassOutlines = true,
  });

  ThemeSettings copyWith({
    ThemeMode? themeMode,
    PlayerView? playerView,

    AppAccent? appAccent,
    bool? useSystemFont,
    String? customFontId,
    String? customFontName,
    double? lyricsTextScale,
    bool? appGlassOutlines,
  }) {
    return ThemeSettings(
      themeMode: themeMode ?? this.themeMode,
      playerView: playerView ?? this.playerView,

      appAccent: appAccent ?? this.appAccent,
      useSystemFont: useSystemFont ?? this.useSystemFont,
      customFontId: customFontId ?? this.customFontId,
      customFontName: customFontName ?? this.customFontName,
      lyricsTextScale: normalizeLyricsTextScale(
        lyricsTextScale ?? this.lyricsTextScale,
      ),
      appGlassOutlines: appGlassOutlines ?? this.appGlassOutlines,
    );
  }

  Map<String, dynamic> toJson() => {
    kThemeModeKey: themeMode.name,
    kPlayerViewKey: playerView.name,
    kAppAccentKey: appAccent.name,
    kUseSystemFontKey: useSystemFont,
    kCustomFontIdKey: customFontId,
    kCustomFontNameKey: customFontName,
    kLyricsTextScaleKey: lyricsTextScale,
    kAppGlassOutlinesKey: appGlassOutlines,
  };

  factory ThemeSettings.fromJson(Map<String, dynamic> json) {
    return ThemeSettings(
      themeMode: themeModeFromString(json[kThemeModeKey] as String?),
      playerView: playerViewFromString(json[kPlayerViewKey]?.toString()),

      appAccent: appAccentFromString(
        json[kAppAccentKey] as String?,
      ),
      useSystemFont: json[kUseSystemFontKey] as bool? ?? false,
      customFontId: json[kCustomFontIdKey] as String? ?? '',
      customFontName: json[kCustomFontNameKey] as String? ?? '',
      lyricsTextScale: normalizeLyricsTextScale(
        json[kLyricsTextScaleKey] as num?,
      ),
      appGlassOutlines: json[kAppGlassOutlinesKey] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThemeSettings &&
        other.themeMode == themeMode &&
        other.playerView == playerView &&
        other.appAccent == appAccent &&
        other.useSystemFont == useSystemFont &&
        other.customFontId == customFontId &&
        other.customFontName == customFontName &&
        other.lyricsTextScale == lyricsTextScale &&
        other.appGlassOutlines == appGlassOutlines;
  }

  @override
  int get hashCode =>
      themeMode.hashCode ^
      playerView.hashCode ^
      appAccent.hashCode ^
      useSystemFont.hashCode ^
      customFontId.hashCode ^
      customFontName.hashCode ^
      lyricsTextScale.hashCode ^
      appGlassOutlines.hashCode;
}

ThemeMode themeModeFromString(String? value) {
  if (value == null) return ThemeMode.system;
  return ThemeMode.values.firstWhere(
    (e) => e.name == value,
    orElse: () => ThemeMode.system,
  );
}
