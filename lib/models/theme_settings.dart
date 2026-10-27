import 'package:flutter/material.dart';

const String kThemeModeKey = 'theme_mode';
const String kSistrumAccentKey = 'sistrum_accent';
const String kUseSystemFontKey = 'use_system_font';
const String kCustomFontIdKey = 'custom_font_id';
const String kCustomFontNameKey = 'custom_font_name';
const String kPlayerViewKey = 'player_view';
const String kLyricsTextScaleKey = 'lyrics_text_scale';

double normalizeLyricsTextScale(num? value) =>
    value != null && value.isFinite ? value.toDouble().clamp(0.8, 1.4) : 1.0;
const String kSistrumGlassOutlinesKey = 'sistrum_glass_outlines';

// Read settings and backups written before the identity change.
const String kLegacyAccentKey = '\u006d\u006f\u0072\u006e\u0079\u0065_accent';
const String kLegacyGlassOutlinesKey =
    '\u006d\u006f\u0072\u006e\u0079\u0065_glass_outlines';

enum PlayerView { normal, immersive }

PlayerView playerViewFromString(String? value) => PlayerView.values.firstWhere(
  (view) => view.name == value,
  orElse: () => PlayerView.normal,
);

enum SistrumAccent { red, orange, green, teal, blue, purple, pink }

SistrumAccent sistrumAccentFromString(String? value) =>
    SistrumAccent.values.firstWhere(
      (accent) => accent.name == value,
      orElse: () => SistrumAccent.red,
    );

class ThemeSettings {
  final ThemeMode themeMode;
  final PlayerView playerView;

  final SistrumAccent sistrumAccent;
  final bool useSystemFont;
  final String customFontId;
  final String customFontName;
  final double lyricsTextScale;
  final bool sistrumGlassOutlines;

  const ThemeSettings({
    this.themeMode = ThemeMode.system,
    this.playerView = PlayerView.normal,

    this.sistrumAccent = SistrumAccent.red,
    this.useSystemFont = false,
    this.customFontId = '',
    this.customFontName = '',
    this.lyricsTextScale = 1,
    this.sistrumGlassOutlines = true,
  });

  ThemeSettings copyWith({
    ThemeMode? themeMode,
    PlayerView? playerView,

    SistrumAccent? sistrumAccent,
    bool? useSystemFont,
    String? customFontId,
    String? customFontName,
    double? lyricsTextScale,
    bool? sistrumGlassOutlines,
  }) {
    return ThemeSettings(
      themeMode: themeMode ?? this.themeMode,
      playerView: playerView ?? this.playerView,

      sistrumAccent: sistrumAccent ?? this.sistrumAccent,
      useSystemFont: useSystemFont ?? this.useSystemFont,
      customFontId: customFontId ?? this.customFontId,
      customFontName: customFontName ?? this.customFontName,
      lyricsTextScale: normalizeLyricsTextScale(
        lyricsTextScale ?? this.lyricsTextScale,
      ),
      sistrumGlassOutlines: sistrumGlassOutlines ?? this.sistrumGlassOutlines,
    );
  }

  Map<String, dynamic> toJson() => {
    kThemeModeKey: themeMode.name,
    kPlayerViewKey: playerView.name,
    kSistrumAccentKey: sistrumAccent.name,
    kUseSystemFontKey: useSystemFont,
    kCustomFontIdKey: customFontId,
    kCustomFontNameKey: customFontName,
    kLyricsTextScaleKey: lyricsTextScale,
    kSistrumGlassOutlinesKey: sistrumGlassOutlines,
  };

  factory ThemeSettings.fromJson(Map<String, dynamic> json) {
    return ThemeSettings(
      themeMode: themeModeFromString(json[kThemeModeKey] as String?),
      playerView: playerViewFromString(json[kPlayerViewKey]?.toString()),

      sistrumAccent: sistrumAccentFromString(
        json[json.containsKey(kSistrumAccentKey)
                ? kSistrumAccentKey
                : kLegacyAccentKey]
            as String?,
      ),
      useSystemFont: json[kUseSystemFontKey] as bool? ?? false,
      customFontId: json[kCustomFontIdKey] as String? ?? '',
      customFontName: json[kCustomFontNameKey] as String? ?? '',
      lyricsTextScale: normalizeLyricsTextScale(
        json[kLyricsTextScaleKey] as num?,
      ),
      sistrumGlassOutlines:
          json[json.containsKey(kSistrumGlassOutlinesKey)
                  ? kSistrumGlassOutlinesKey
                  : kLegacyGlassOutlinesKey]
              as bool? ??
          true,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThemeSettings &&
        other.themeMode == themeMode &&
        other.playerView == playerView &&
        other.sistrumAccent == sistrumAccent &&
        other.useSystemFont == useSystemFont &&
        other.customFontId == customFontId &&
        other.customFontName == customFontName &&
        other.lyricsTextScale == lyricsTextScale &&
        other.sistrumGlassOutlines == sistrumGlassOutlines;
  }

  @override
  int get hashCode =>
      themeMode.hashCode ^
      playerView.hashCode ^
      sistrumAccent.hashCode ^
      useSystemFont.hashCode ^
      customFontId.hashCode ^
      customFontName.hashCode ^
      lyricsTextScale.hashCode ^
      sistrumGlassOutlines.hashCode;
}

ThemeMode themeModeFromString(String? value) {
  if (value == null) return ThemeMode.system;
  return ThemeMode.values.firstWhere(
    (e) => e.name == value,
    orElse: () => ThemeMode.system,
  );
}
