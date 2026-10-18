import 'package:json_annotation/json_annotation.dart';
import 'package:spotiflac_android/models/automix_options.dart';
import 'package:spotiflac_android/utils/artist_utils.dart';

part 'settings.g.dart';

@JsonSerializable()
class AppSettings {
  static const String libraryQualityLabelBitrate = 'bitrate';
  static const String libraryQualityLabelFileFormat = 'file_format';
  static const String libraryQualityLabelBitDepthOnly = 'bit_depth_only';
  static const String libraryQualityLabelBitDepth = 'bit_depth';
  static const String libraryQualityLabelBitDepthBitrate = 'bit_depth_bitrate';

  final String downloadDirectory;
  final String downloadDirectoryBookmark;
  final String storageMode; // 'app' or 'saf'
  final String downloadTreeUri; // SAF persistable tree URI

  /// Maximum width or height of selected local artwork before embedding.
  /// Zero preserves the original image.
  final int embeddedCoverMaxDimension;
  final String
  artistTagMode; // 'joined', 'split_vorbis' (Vorbis formats), or 'primary'
  final bool embedLyrics;
  // Apply ReplayGain/R128 tags as volume normalization in the built-in player.
  final bool playbackNormalization;
  final bool pauseOnMute;
  final bool playOnHeadphonesConnected;
  final bool autoMix;
  @JsonKey(fromJson: autoMixDurationFromJson)
  final int autoMixDuration;
  @JsonKey(unknownEnumValue: AutoMixEffect.auto)
  final AutoMixEffect autoMixEffect;
  @JsonKey(fromJson: autoMixSpeedFromJson)
  final double autoMixSpeed;
  @JsonKey(fromJson: autoMixPitchFromJson)
  final double autoMixPitch;
  final bool autoMixEcho;
  final bool autoMixLowPass;
  AutoMixOptions get autoMixOptions => AutoMixOptions(
    durationSeconds: autoMixDuration,
    effect: autoMixEffect,
    speed: autoMixSpeed,
    pitchSemitones: autoMixPitch,
    echo: autoMixEcho,
    lowPass: autoMixLowPass,
  );
  final bool usbBitPerfect;
  final bool usbDirect;
  final bool usbDsdOverPcm;
  final bool usbAllowFixedVolume;
  final bool dapExclusive;
  final bool autoplay;
  final bool autoplayPersonalization;
  final bool isFirstLaunch;
  final bool hasSearchedBefore;
  final String albumFolderStructure;
  final String historyViewMode;
  final String historyFilterMode;

  /// Library view opened when switching to the Library tab:
  /// 'last' (keep last used), 'all', 'albums', 'singles', or 'playlists'.
  final String defaultLibraryView;

  /// Library badge text: measured bitrate, file format, bit depth,
  /// bit depth/sample rate, or the combined bit depth/bitrate label.
  final String libraryQualityLabelMode;
  final bool enableLogging;
  final bool heroAnimationsEnabled;

  /// Forces the shell's backdrop blur on even when the startup runtime
  /// profile disabled it for this device tier. Off means "follow the
  /// device default".
  final bool forceBackdropBlur;
  final String locale;
  final String lyricsMode;
  final bool keepScreenOnLyrics;
  final bool listeningStatisticsEnabled;

  final bool localLibraryEnabled;
  final String localLibraryPath;
  final String
  localLibraryBookmark; // Base64-encoded iOS security-scoped bookmark
  final bool localLibraryShowDuplicates;
  final String
  localLibraryAutoScan; // Auto-scan mode: 'off', 'on_open', 'daily', 'weekly'

  final bool hasCompletedTutorial;

  final String
  lastSeenVersion; // Last app version the user has acknowledged (e.g. '3.7.0')

  final bool playerShowPronunciation;
  final bool playerShowTranslation;

  const AppSettings({
    this.downloadDirectory = '',
    this.downloadDirectoryBookmark = '',
    this.storageMode = 'app',
    this.downloadTreeUri = '',
    this.embeddedCoverMaxDimension = 0,
    this.artistTagMode = artistTagModeJoined,
    this.embedLyrics = true,
    this.playbackNormalization = false,
    this.pauseOnMute = true,
    this.playOnHeadphonesConnected = false,
    this.autoMix = false,
    this.autoMixDuration = 0,
    this.autoMixEffect = AutoMixEffect.auto,
    this.autoMixSpeed = 1,
    this.autoMixPitch = 0,
    this.autoMixEcho = false,
    this.autoMixLowPass = false,
    this.usbBitPerfect = false,
    this.usbDirect = false,
    this.usbDsdOverPcm = false,
    this.usbAllowFixedVolume = false,
    this.dapExclusive = false,
    this.autoplay = false,
    this.autoplayPersonalization = false,
    this.isFirstLaunch = true,
    this.hasSearchedBefore = false,
    this.albumFolderStructure = 'artist_album',
    this.historyViewMode = 'grid',
    this.historyFilterMode = 'all',
    this.defaultLibraryView = 'last',
    this.libraryQualityLabelMode = AppSettings.libraryQualityLabelBitrate,
    this.enableLogging = false,
    this.heroAnimationsEnabled = true,
    this.forceBackdropBlur = false,
    this.locale = 'system',
    this.lyricsMode = 'embed',
    this.keepScreenOnLyrics = true,
    this.listeningStatisticsEnabled = true,
    this.localLibraryEnabled = false,
    this.localLibraryPath = '',
    this.localLibraryBookmark = '',
    this.localLibraryShowDuplicates = true,
    this.localLibraryAutoScan = 'off',
    this.hasCompletedTutorial = false,
    this.lastSeenVersion = '',
    this.playerShowPronunciation = true,
    this.playerShowTranslation = true,
  });

  AppSettings copyWith({
    String? downloadDirectory,
    String? downloadDirectoryBookmark,
    String? storageMode,
    String? downloadTreeUri,
    int? embeddedCoverMaxDimension,
    String? artistTagMode,
    bool? embedLyrics,
    bool? playbackNormalization,
    bool? pauseOnMute,
    bool? playOnHeadphonesConnected,
    bool? autoMix,
    int? autoMixDuration,
    AutoMixEffect? autoMixEffect,
    double? autoMixSpeed,
    double? autoMixPitch,
    bool? autoMixEcho,
    bool? autoMixLowPass,
    bool? usbBitPerfect,
    bool? usbDirect,
    bool? usbDsdOverPcm,
    bool? usbAllowFixedVolume,
    bool? dapExclusive,
    bool? autoplay,
    bool? autoplayPersonalization,
    bool? isFirstLaunch,
    bool? hasSearchedBefore,
    String? albumFolderStructure,
    String? historyViewMode,
    String? historyFilterMode,
    String? defaultLibraryView,
    String? libraryQualityLabelMode,
    bool? enableLogging,
    bool? heroAnimationsEnabled,
    bool? forceBackdropBlur,
    String? locale,
    String? lyricsMode,
    bool? keepScreenOnLyrics,
    bool? listeningStatisticsEnabled,
    bool? localLibraryEnabled,
    String? localLibraryPath,
    String? localLibraryBookmark,
    bool? localLibraryShowDuplicates,
    String? localLibraryAutoScan,
    bool? hasCompletedTutorial,
    String? lastSeenVersion,
    bool? playerShowPronunciation,
    bool? playerShowTranslation,
  }) {
    return AppSettings(
      downloadDirectory: downloadDirectory ?? this.downloadDirectory,
      downloadDirectoryBookmark:
          downloadDirectoryBookmark ?? this.downloadDirectoryBookmark,
      storageMode: storageMode ?? this.storageMode,
      downloadTreeUri: downloadTreeUri ?? this.downloadTreeUri,
      embeddedCoverMaxDimension:
          embeddedCoverMaxDimension ?? this.embeddedCoverMaxDimension,
      artistTagMode: artistTagMode ?? this.artistTagMode,
      embedLyrics: embedLyrics ?? this.embedLyrics,
      playbackNormalization:
          playbackNormalization ?? this.playbackNormalization,
      pauseOnMute: pauseOnMute ?? this.pauseOnMute,
      playOnHeadphonesConnected:
          playOnHeadphonesConnected ?? this.playOnHeadphonesConnected,
      autoMix: autoMix ?? this.autoMix,
      autoMixDuration: autoMixDuration ?? this.autoMixDuration,
      autoMixEffect: autoMixEffect ?? this.autoMixEffect,
      autoMixSpeed: autoMixSpeed ?? this.autoMixSpeed,
      autoMixPitch: autoMixPitch ?? this.autoMixPitch,
      autoMixEcho: autoMixEcho ?? this.autoMixEcho,
      autoMixLowPass: autoMixLowPass ?? this.autoMixLowPass,
      usbBitPerfect: usbBitPerfect ?? this.usbBitPerfect,
      usbDirect: usbDirect ?? this.usbDirect,
      usbDsdOverPcm: usbDsdOverPcm ?? this.usbDsdOverPcm,
      usbAllowFixedVolume: usbAllowFixedVolume ?? this.usbAllowFixedVolume,
      dapExclusive: dapExclusive ?? this.dapExclusive,
      autoplay: autoplay ?? this.autoplay,
      autoplayPersonalization:
          autoplayPersonalization ?? this.autoplayPersonalization,
      isFirstLaunch: isFirstLaunch ?? this.isFirstLaunch,
      hasSearchedBefore: hasSearchedBefore ?? this.hasSearchedBefore,
      albumFolderStructure: albumFolderStructure ?? this.albumFolderStructure,
      historyViewMode: historyViewMode ?? this.historyViewMode,
      historyFilterMode: historyFilterMode ?? this.historyFilterMode,
      defaultLibraryView: defaultLibraryView ?? this.defaultLibraryView,
      libraryQualityLabelMode:
          libraryQualityLabelMode ?? this.libraryQualityLabelMode,
      enableLogging: enableLogging ?? this.enableLogging,
      heroAnimationsEnabled:
          heroAnimationsEnabled ?? this.heroAnimationsEnabled,
      forceBackdropBlur: forceBackdropBlur ?? this.forceBackdropBlur,
      locale: locale ?? this.locale,
      lyricsMode: lyricsMode ?? this.lyricsMode,
      keepScreenOnLyrics: keepScreenOnLyrics ?? this.keepScreenOnLyrics,
      listeningStatisticsEnabled:
          listeningStatisticsEnabled ?? this.listeningStatisticsEnabled,
      localLibraryEnabled: localLibraryEnabled ?? this.localLibraryEnabled,
      localLibraryPath: localLibraryPath ?? this.localLibraryPath,
      localLibraryBookmark: localLibraryBookmark ?? this.localLibraryBookmark,
      localLibraryShowDuplicates:
          localLibraryShowDuplicates ?? this.localLibraryShowDuplicates,
      localLibraryAutoScan: localLibraryAutoScan ?? this.localLibraryAutoScan,
      hasCompletedTutorial: hasCompletedTutorial ?? this.hasCompletedTutorial,
      lastSeenVersion: lastSeenVersion ?? this.lastSeenVersion,
      playerShowPronunciation:
          playerShowPronunciation ?? this.playerShowPronunciation,
      playerShowTranslation:
          playerShowTranslation ?? this.playerShowTranslation,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(json);
  Map<String, dynamic> toJson() => _$AppSettingsToJson(this);
}
