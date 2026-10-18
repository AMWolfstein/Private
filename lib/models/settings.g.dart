// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppSettings _$AppSettingsFromJson(Map<String, dynamic> json) => AppSettings(
  downloadDirectory: json['downloadDirectory'] as String? ?? '',
  downloadDirectoryBookmark: json['downloadDirectoryBookmark'] as String? ?? '',
  storageMode: json['storageMode'] as String? ?? 'app',
  downloadTreeUri: json['downloadTreeUri'] as String? ?? '',
  embedMetadata: json['embedMetadata'] as bool? ?? true,
  embeddedCoverMaxDimension:
      (json['embeddedCoverMaxDimension'] as num?)?.toInt() ?? 0,
  artistTagMode: json['artistTagMode'] as String? ?? artistTagModeJoined,
  embedLyrics: json['embedLyrics'] as bool? ?? true,
  embedReplayGain: json['embedReplayGain'] as bool? ?? false,
  playbackNormalization: json['playbackNormalization'] as bool? ?? false,
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
  autoplayPersonalization: json['autoplayPersonalization'] as bool? ?? false,
  isFirstLaunch: json['isFirstLaunch'] as bool? ?? true,
  hasSearchedBefore: json['hasSearchedBefore'] as bool? ?? false,
  albumFolderStructure:
      json['albumFolderStructure'] as String? ?? 'artist_album',
  historyViewMode: json['historyViewMode'] as String? ?? 'grid',
  historyFilterMode: json['historyFilterMode'] as String? ?? 'all',
  defaultLibraryView: json['defaultLibraryView'] as String? ?? 'last',
  libraryQualityLabelMode:
      json['libraryQualityLabelMode'] as String? ??
      AppSettings.libraryQualityLabelBitrate,
  enableLogging: json['enableLogging'] as bool? ?? false,
  heroAnimationsEnabled: json['heroAnimationsEnabled'] as bool? ?? true,
  forceBackdropBlur: json['forceBackdropBlur'] as bool? ?? false,
  locale: json['locale'] as String? ?? 'system',
  lyricsMode: json['lyricsMode'] as String? ?? 'embed',
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
  lyricsProviders:
      (json['lyricsProviders'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const ['apple_music', 'lrclib'],
  lyricsIncludeTranslationNetease:
      json['lyricsIncludeTranslationNetease'] as bool? ?? false,
  lyricsIncludeRomanizationNetease:
      json['lyricsIncludeRomanizationNetease'] as bool? ?? false,
  lyricsMultiPersonWordByWord:
      json['lyricsMultiPersonWordByWord'] as bool? ?? true,
  lyricsAppleElrcWordSync: json['lyricsAppleElrcWordSync'] as bool? ?? true,
  musixmatchLanguage: json['musixmatchLanguage'] as String? ?? '',
  lastSeenVersion: json['lastSeenVersion'] as String? ?? '',
  playerMode: json['playerMode'] as String? ?? 'internal',
  playerShowPronunciation: json['playerShowPronunciation'] as bool? ?? true,
  playerShowTranslation: json['playerShowTranslation'] as bool? ?? true,
);

Map<String, dynamic> _$AppSettingsToJson(
  AppSettings instance,
) => <String, dynamic>{
  'downloadDirectory': instance.downloadDirectory,
  'downloadDirectoryBookmark': instance.downloadDirectoryBookmark,
  'storageMode': instance.storageMode,
  'downloadTreeUri': instance.downloadTreeUri,
  'embedMetadata': instance.embedMetadata,
  'embeddedCoverMaxDimension': instance.embeddedCoverMaxDimension,
  'artistTagMode': instance.artistTagMode,
  'embedLyrics': instance.embedLyrics,
  'embedReplayGain': instance.embedReplayGain,
  'playbackNormalization': instance.playbackNormalization,
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
  'hasSearchedBefore': instance.hasSearchedBefore,
  'albumFolderStructure': instance.albumFolderStructure,
  'historyViewMode': instance.historyViewMode,
  'historyFilterMode': instance.historyFilterMode,
  'defaultLibraryView': instance.defaultLibraryView,
  'libraryQualityLabelMode': instance.libraryQualityLabelMode,
  'enableLogging': instance.enableLogging,
  'heroAnimationsEnabled': instance.heroAnimationsEnabled,
  'forceBackdropBlur': instance.forceBackdropBlur,
  'locale': instance.locale,
  'lyricsMode': instance.lyricsMode,
  'keepScreenOnLyrics': instance.keepScreenOnLyrics,
  'listeningStatisticsEnabled': instance.listeningStatisticsEnabled,
  'localLibraryEnabled': instance.localLibraryEnabled,
  'localLibraryPath': instance.localLibraryPath,
  'localLibraryBookmark': instance.localLibraryBookmark,
  'localLibraryShowDuplicates': instance.localLibraryShowDuplicates,
  'localLibraryAutoScan': instance.localLibraryAutoScan,
  'hasCompletedTutorial': instance.hasCompletedTutorial,
  'lyricsProviders': instance.lyricsProviders,
  'lyricsIncludeTranslationNetease': instance.lyricsIncludeTranslationNetease,
  'lyricsIncludeRomanizationNetease': instance.lyricsIncludeRomanizationNetease,
  'lyricsMultiPersonWordByWord': instance.lyricsMultiPersonWordByWord,
  'lyricsAppleElrcWordSync': instance.lyricsAppleElrcWordSync,
  'musixmatchLanguage': instance.musixmatchLanguage,
  'lastSeenVersion': instance.lastSeenVersion,
  'playerMode': instance.playerMode,
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
