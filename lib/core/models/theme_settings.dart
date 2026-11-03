import 'package:flutter/material.dart';

const String kThemeModeKey = 'theme_mode';
const String kPlayerViewKey = 'player_view';
const String kLyricsTimingOffsetKey = 'lyrics_timing_offset_ms';

int normalizeLyricsTimingOffset(num? value) =>
    value != null && value.isFinite ? value.round().clamp(-2000, 2000) : 0;

const String kLyricsTextScaleKey = 'lyrics_text_scale';
const String kLyricsBlurKey = 'lyrics_blur';

double normalizeLyricsBlur(num? value) =>
    value != null && value.isFinite ? value.toDouble().clamp(0.0, 1.5) : 1.0;

double normalizeLyricsTextScale(num? value) =>
    value != null && value.isFinite ? value.toDouble().clamp(0.8, 1.4) : 1.0;

enum PlayerView { normal, immersive }

PlayerView playerViewFromString(String? value) => PlayerView.values.firstWhere(
  (view) => view.name == value,
  orElse: () => PlayerView.normal,
);

class ThemeSettings {
  final ThemeMode themeMode;
  final PlayerView playerView;

  final double lyricsTextScale;
  final double lyricsBlur;
  final int lyricsTimingOffsetMs;

  const ThemeSettings({
    this.themeMode = ThemeMode.system,
    this.playerView = PlayerView.normal,

    this.lyricsTextScale = 1,
    this.lyricsBlur = 1,
    this.lyricsTimingOffsetMs = 0,
  });

  ThemeSettings copyWith({
    ThemeMode? themeMode,
    PlayerView? playerView,

    double? lyricsTextScale,
    double? lyricsBlur,
    int? lyricsTimingOffsetMs,
  }) {
    return ThemeSettings(
      themeMode: themeMode ?? this.themeMode,
      playerView: playerView ?? this.playerView,

      lyricsTextScale: normalizeLyricsTextScale(
        lyricsTextScale ?? this.lyricsTextScale,
      ),
      lyricsBlur: normalizeLyricsBlur(lyricsBlur ?? this.lyricsBlur),
      lyricsTimingOffsetMs: normalizeLyricsTimingOffset(
        lyricsTimingOffsetMs ?? this.lyricsTimingOffsetMs,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    kThemeModeKey: themeMode.name,
    kPlayerViewKey: playerView.name,
    kLyricsTextScaleKey: lyricsTextScale,
    kLyricsBlurKey: normalizeLyricsBlur(lyricsBlur),
    kLyricsTimingOffsetKey: normalizeLyricsTimingOffset(lyricsTimingOffsetMs),
  };

  factory ThemeSettings.fromJson(Map<String, dynamic> json) {
    return ThemeSettings(
      themeMode: themeModeFromString(json[kThemeModeKey] as String?),
      playerView: playerViewFromString(json[kPlayerViewKey]?.toString()),

      lyricsTextScale: normalizeLyricsTextScale(
        json[kLyricsTextScaleKey] as num?,
      ),
      lyricsBlur: normalizeLyricsBlur(
        json[kLyricsBlurKey] is num ? json[kLyricsBlurKey] as num : null,
      ),
      lyricsTimingOffsetMs: normalizeLyricsTimingOffset(
        json[kLyricsTimingOffsetKey] as num?,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThemeSettings &&
        other.themeMode == themeMode &&
        other.playerView == playerView &&
        other.lyricsTextScale == lyricsTextScale &&
        other.lyricsBlur == lyricsBlur &&
        other.lyricsTimingOffsetMs == lyricsTimingOffsetMs;
  }

  @override
  int get hashCode =>
      themeMode.hashCode ^
      playerView.hashCode ^
      lyricsTextScale.hashCode ^
      lyricsBlur.hashCode ^
      lyricsTimingOffsetMs.hashCode;
}

ThemeMode themeModeFromString(String? value) {
  if (value == null) return ThemeMode.system;
  return ThemeMode.values.firstWhere(
    (e) => e.name == value,
    orElse: () => ThemeMode.system,
  );
}
