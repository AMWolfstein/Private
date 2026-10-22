import 'package:flutter/material.dart';

const String kThemeModeKey = 'theme_mode';
const String kMornyeAccentKey = 'mornye_accent';
const String kUseSystemFontKey = 'use_system_font';
const String kCustomFontIdKey = 'custom_font_id';
const String kCustomFontNameKey = 'custom_font_name';
const String kPlayerViewKey = 'player_view';
const String kLyricsTextScaleKey = 'lyrics_text_scale';

double normalizeLyricsTextScale(num? value) =>
    value != null && value.isFinite ? value.toDouble().clamp(0.8, 1.4) : 1.0;
const String kMornyeGlassOutlinesKey = 'mornye_glass_outlines';

enum PlayerView { normal, immersive }

PlayerView playerViewFromString(String? value) => PlayerView.values.firstWhere(
  (view) => view.name == value,
  orElse: () => PlayerView.normal,
);

enum MornyeAccent { red, orange, green, teal, blue, purple, pink }

MornyeAccent mornyeAccentFromString(String? value) =>
    MornyeAccent.values.firstWhere(
      (accent) => accent.name == value,
      orElse: () => MornyeAccent.red,
    );

class ThemeSettings {
  final ThemeMode themeMode;
  final PlayerView playerView;

  final MornyeAccent mornyeAccent;
  final bool useSystemFont;
  final String customFontId;
  final String customFontName;
  final double lyricsTextScale;
  final bool mornyeGlassOutlines;

  const ThemeSettings({
    this.themeMode = ThemeMode.system,
    this.playerView = PlayerView.normal,

    this.mornyeAccent = MornyeAccent.red,
    this.useSystemFont = false,
    this.customFontId = '',
    this.customFontName = '',
    this.lyricsTextScale = 1,
    this.mornyeGlassOutlines = true,
  });

  ThemeSettings copyWith({
    ThemeMode? themeMode,
    PlayerView? playerView,

    MornyeAccent? mornyeAccent,
    bool? useSystemFont,
    String? customFontId,
    String? customFontName,
    double? lyricsTextScale,
    bool? mornyeGlassOutlines,
  }) {
    return ThemeSettings(
      themeMode: themeMode ?? this.themeMode,
      playerView: playerView ?? this.playerView,

      mornyeAccent: mornyeAccent ?? this.mornyeAccent,
      useSystemFont: useSystemFont ?? this.useSystemFont,
      customFontId: customFontId ?? this.customFontId,
      customFontName: customFontName ?? this.customFontName,
      lyricsTextScale: normalizeLyricsTextScale(
        lyricsTextScale ?? this.lyricsTextScale,
      ),
      mornyeGlassOutlines: mornyeGlassOutlines ?? this.mornyeGlassOutlines,
    );
  }

  Map<String, dynamic> toJson() => {
    kThemeModeKey: themeMode.name,
    kPlayerViewKey: playerView.name,
    kMornyeAccentKey: mornyeAccent.name,
    kUseSystemFontKey: useSystemFont,
    kCustomFontIdKey: customFontId,
    kCustomFontNameKey: customFontName,
    kLyricsTextScaleKey: lyricsTextScale,
    kMornyeGlassOutlinesKey: mornyeGlassOutlines,
  };

  factory ThemeSettings.fromJson(Map<String, dynamic> json) {
    return ThemeSettings(
      themeMode: themeModeFromString(json[kThemeModeKey] as String?),
      playerView: playerViewFromString(json[kPlayerViewKey]?.toString()),

      mornyeAccent: mornyeAccentFromString(json[kMornyeAccentKey] as String?),
      useSystemFont: json[kUseSystemFontKey] as bool? ?? false,
      customFontId: json[kCustomFontIdKey] as String? ?? '',
      customFontName: json[kCustomFontNameKey] as String? ?? '',
      lyricsTextScale: normalizeLyricsTextScale(
        json[kLyricsTextScaleKey] as num?,
      ),
      mornyeGlassOutlines: json[kMornyeGlassOutlinesKey] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThemeSettings &&
        other.themeMode == themeMode &&
        other.playerView == playerView &&
        other.mornyeAccent == mornyeAccent &&
        other.useSystemFont == useSystemFont &&
        other.customFontId == customFontId &&
        other.customFontName == customFontName &&
        other.lyricsTextScale == lyricsTextScale &&
        other.mornyeGlassOutlines == mornyeGlassOutlines;
  }

  @override
  int get hashCode =>
      themeMode.hashCode ^
      playerView.hashCode ^
      mornyeAccent.hashCode ^
      useSystemFont.hashCode ^
      customFontId.hashCode ^
      customFontName.hashCode ^
      lyricsTextScale.hashCode ^
      mornyeGlassOutlines.hashCode;
}

ThemeMode themeModeFromString(String? value) {
  if (value == null) return ThemeMode.system;
  return ThemeMode.values.firstWhere(
    (e) => e.name == value,
    orElse: () => ThemeMode.system,
  );
}
