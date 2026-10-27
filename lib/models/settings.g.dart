// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppSettings _$AppSettingsFromJson(Map<String, dynamic> json) => AppSettings(
  metadataSeparators: json['metadataSeparators'] == null
      ? const MetadataSeparators()
      : MetadataSeparators.fromJson(
          json['metadataSeparators'] as Map<String, dynamic>,
        ),
  musicHaptics: json['musicHaptics'] as bool? ?? false,
  musicHapticsSensitivity: json['musicHapticsSensitivity'] == null
      ? 0.5
      : musicHapticsLevelFromJson(json['musicHapticsSensitivity']),
  musicHapticsStrength: json['musicHapticsStrength'] == null
      ? 0.5
      : musicHapticsLevelFromJson(json['musicHapticsStrength']),
  playbackNormalization: json['playbackNormalization'] as bool? ?? false,
  playbackNormalizationPreamp: json['playbackNormalizationPreamp'] == null
      ? 0
      : playbackNormalizationPreampFromJson(
          json['playbackNormalizationPreamp'],
        ),
  playbackNormalizationMode: json['playbackNormalizationMode'] == null
      ? 'track'
      : playbackNormalizationModeFromJson(json['playbackNormalizationMode']),
  pauseOnMute: json['pauseOnMute'] as bool? ?? true,
  playOnHeadphonesConnected:
      json['playOnHeadphonesConnected'] as bool? ?? false,
  autoMix: json['autoMix'] as bool? ?? false,
  autoMixDuration: json['autoMixDuration'] == null
      ? 0
      : autoMixDurationFromJson(json['autoMixDuration']),
  autoMixEffect:
      $enumDecodeNullable(
        _$AutoMixEffectEnumMap,
        json['autoMixEffect'],
        unknownValue: AutoMixEffect.auto,
      ) ??
      AutoMixEffect.auto,
  autoMixSpeed: json['autoMixSpeed'] == null
      ? 1
      : autoMixSpeedFromJson(json['autoMixSpeed']),
  autoMixPitch: json['autoMixPitch'] == null
      ? 0
      : autoMixPitchFromJson(json['autoMixPitch']),
  autoMixEcho: json['autoMixEcho'] as bool? ?? false,
  autoMixLowPass: json['autoMixLowPass'] as bool? ?? false,
  usbBitPerfect: json['usbBitPerfect'] as bool? ?? false,
  usbDirect: json['usbDirect'] as bool? ?? false,
  usbDsdOverPcm: json['usbDsdOverPcm'] as bool? ?? false,
  usbAllowFixedVolume: json['usbAllowFixedVolume'] as bool? ?? false,
  dapExclusive: json['dapExclusive'] as bool? ?? false,
  autoplay: json['autoplay'] as bool? ?? false,
  autoplayPersonalization: json['autoplayPersonalization'] as bool? ?? true,
  isFirstLaunch: json['isFirstLaunch'] as bool? ?? true,
  historyFilterMode: json['historyFilterMode'] as String? ?? 'all',
  enableLogging: json['enableLogging'] as bool? ?? false,
  heroAnimationsEnabled: json['heroAnimationsEnabled'] as bool? ?? true,
  developerOptionsUnlocked: json['developerOptionsUnlocked'] as bool? ?? false,
  performanceHudEnabled: json['performanceHudEnabled'] as bool? ?? false,
  barSamplerDisabled: json['barSamplerDisabled'] as bool? ?? false,
  headerBandBlurDisabled: json['headerBandBlurDisabled'] as bool? ?? false,
  glassQuality: json['glassQuality'] as String? ?? 'auto',
  glassClarityLevel: json['glassClarityLevel'] == null
      ? kDefaultGlassClarityLevel
      : glassClarityLevelFromJson(json['glassClarityLevel']),
  locale: json['locale'] == null ? 'system' : appLocaleFromJson(json['locale']),
  keepScreenOnLyrics: json['keepScreenOnLyrics'] as bool? ?? true,
  listeningStatisticsEnabled:
      json['listeningStatisticsEnabled'] as bool? ?? true,
  localLibraryEnabled: json['localLibraryEnabled'] as bool? ?? false,
  localLibraryPath: json['localLibraryPath'] as String? ?? '',
  localLibraryBookmark: json['localLibraryBookmark'] as String? ?? '',
  localLibraryShowDuplicates:
      json['localLibraryShowDuplicates'] as bool? ?? true,
  localLibraryAutoScan: json['localLibraryAutoScan'] as String? ?? 'off',
  hasCompletedTutorial: json['hasCompletedTutorial'] as bool? ?? false,
  playerShowPronunciation: json['playerShowPronunciation'] as bool? ?? true,
  playerShowTranslation: json['playerShowTranslation'] as bool? ?? true,
);

Map<String, dynamic> _$AppSettingsToJson(AppSettings instance) =>
    <String, dynamic>{
      'metadataSeparators': instance.metadataSeparators.toJson(),
      'musicHaptics': instance.musicHaptics,
      'musicHapticsSensitivity': instance.musicHapticsSensitivity,
      'musicHapticsStrength': instance.musicHapticsStrength,
      'playbackNormalization': instance.playbackNormalization,
      'playbackNormalizationPreamp': instance.playbackNormalizationPreamp,
      'playbackNormalizationMode': instance.playbackNormalizationMode,
      'pauseOnMute': instance.pauseOnMute,
      'playOnHeadphonesConnected': instance.playOnHeadphonesConnected,
      'autoMix': instance.autoMix,
      'autoMixDuration': instance.autoMixDuration,
      'autoMixEffect': _$AutoMixEffectEnumMap[instance.autoMixEffect]!,
      'autoMixSpeed': instance.autoMixSpeed,
      'autoMixPitch': instance.autoMixPitch,
      'autoMixEcho': instance.autoMixEcho,
      'autoMixLowPass': instance.autoMixLowPass,
      'usbBitPerfect': instance.usbBitPerfect,
      'usbDirect': instance.usbDirect,
      'usbDsdOverPcm': instance.usbDsdOverPcm,
      'usbAllowFixedVolume': instance.usbAllowFixedVolume,
      'dapExclusive': instance.dapExclusive,
      'autoplay': instance.autoplay,
      'autoplayPersonalization': instance.autoplayPersonalization,
      'isFirstLaunch': instance.isFirstLaunch,
      'historyFilterMode': instance.historyFilterMode,
      'enableLogging': instance.enableLogging,
      'heroAnimationsEnabled': instance.heroAnimationsEnabled,
      'developerOptionsUnlocked': instance.developerOptionsUnlocked,
      'performanceHudEnabled': instance.performanceHudEnabled,
      'barSamplerDisabled': instance.barSamplerDisabled,
      'headerBandBlurDisabled': instance.headerBandBlurDisabled,
      'glassQuality': instance.glassQuality,
      'glassClarityLevel': instance.glassClarityLevel,
      'locale': instance.locale,
      'keepScreenOnLyrics': instance.keepScreenOnLyrics,
      'listeningStatisticsEnabled': instance.listeningStatisticsEnabled,
      'localLibraryEnabled': instance.localLibraryEnabled,
      'localLibraryPath': instance.localLibraryPath,
      'localLibraryBookmark': instance.localLibraryBookmark,
      'localLibraryShowDuplicates': instance.localLibraryShowDuplicates,
      'localLibraryAutoScan': instance.localLibraryAutoScan,
      'hasCompletedTutorial': instance.hasCompletedTutorial,
      'playerShowPronunciation': instance.playerShowPronunciation,
      'playerShowTranslation': instance.playerShowTranslation,
    };

const _$AutoMixEffectEnumMap = {
  AutoMixEffect.auto: 'auto',
  AutoMixEffect.crossfade: 'crossfade',
  AutoMixEffect.muffled: 'muffled',
  AutoMixEffect.echo: 'echo',
  AutoMixEffect.pitch: 'pitch',
  AutoMixEffect.custom: 'custom',
};
