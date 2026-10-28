import 'package:json_annotation/json_annotation.dart';
import 'package:sistrum/models/automix_options.dart';
import 'package:sistrum/models/metadata_separators.dart';

part 'settings.g.dart';

/// Pre-amp applied on top of ReplayGain during playback, in whole dB.
/// -7 dB targets -25 LUFS from the -18 LUFS tag reference.
double playbackNormalizationPreampFromJson(Object? value) =>
    value is num && value.isFinite
    ? value.toDouble().roundToDouble().clamp(-15, 6)
    : 0;

String playbackNormalizationModeFromJson(Object? value) =>
    value == 'album' ? 'album' : 'track';

/// Default Sistrum glass clarity level (Balanced).
const int kDefaultGlassClarityLevel = 3;

int glassClarityLevelFromJson(Object? value) => value is num && value.isFinite
    ? value.round().clamp(1, 5)
    : kDefaultGlassClarityLevel;

String appLocaleFromJson(Object? value) => value is String ? value : 'system';

double musicHapticsLevelFromJson(Object? value) =>
    value is num && value.isFinite ? value.toDouble().clamp(0, 1) : 0.5;

@JsonSerializable(explicitToJson: true)
class AppSettings {
  final MetadataSeparators metadataSeparators;
  // Optional pulses follow local playback.
  final bool musicHaptics;
  @JsonKey(fromJson: musicHapticsLevelFromJson)
  final double musicHapticsSensitivity;
  @JsonKey(fromJson: musicHapticsLevelFromJson)
  final double musicHapticsStrength;
  // Apply ReplayGain/R128 tags as volume normalization in the built-in player.
  final bool playbackNormalization;
  @JsonKey(fromJson: playbackNormalizationPreampFromJson)
  final double playbackNormalizationPreamp;
  @JsonKey(fromJson: playbackNormalizationModeFromJson)
  final String playbackNormalizationMode;
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

  final String libraryFilterMode;

  final bool enableLogging;
  final bool heroAnimationsEnabled;

  /// Slow Ken Burns drift on album cover headers.
  final bool animatedAlbumArtwork;

  /// Offer new GitHub releases at startup. Versions far behind still prompt.
  final bool checkForUpdates;

  /// `stable` or `preview` (includes pre-releases).
  final String updateChannel;

  /// Revealed by tapping the About version row seven times.
  final bool developerOptionsUnlocked;

  /// Floating frame-timing overlay (a developer option).
  final bool performanceHudEnabled;

  /// Developer A/B switch: no backdrop sampling for the bottom bar's palette.
  final bool barSamplerDisabled;

  /// Developer A/B switch: the header backing band keeps its tint but drops
  /// its backdrop blur.
  final bool headerBandBlurDisabled;

  /// Sistrum glass renderer: `auto` (the device decides), `lite`, `full` or
  /// `off`. See [SistrumGlassQuality].
  final String glassQuality;

  /// Sistrum glass clarity level, 1 (Frosted) to 5 (Crystal).
  @JsonKey(fromJson: glassClarityLevelFromJson)
  final int glassClarityLevel;
  @JsonKey(fromJson: appLocaleFromJson)
  final String locale;
  final bool keepScreenOnLyrics;
  final bool listeningStatisticsEnabled;

  final bool localLibraryShowDuplicates;
  final String
  localLibraryAutoScan; // Auto-scan mode: 'off', 'on_open', 'daily', 'weekly'

  final bool hasCompletedTutorial;

  final bool playerShowPronunciation;
  final bool playerShowTranslation;

  const AppSettings({
    this.metadataSeparators = const MetadataSeparators(),
    this.musicHaptics = false,
    this.musicHapticsSensitivity = 0.5,
    this.musicHapticsStrength = 0.5,
    this.playbackNormalization = false,
    this.playbackNormalizationPreamp = 0,
    this.playbackNormalizationMode = 'track',
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
    this.autoplayPersonalization = true,
    this.isFirstLaunch = true,

    this.libraryFilterMode = 'all',
    this.enableLogging = false,
    this.heroAnimationsEnabled = true,
    this.animatedAlbumArtwork = true,
    this.checkForUpdates = true,
    this.updateChannel = 'stable',
    this.developerOptionsUnlocked = false,
    this.performanceHudEnabled = false,
    this.barSamplerDisabled = false,
    this.headerBandBlurDisabled = false,
    this.glassQuality = 'auto',
    this.glassClarityLevel = kDefaultGlassClarityLevel,
    this.locale = 'system',
    this.keepScreenOnLyrics = true,
    this.listeningStatisticsEnabled = true,
    this.localLibraryShowDuplicates = true,
    this.localLibraryAutoScan = 'off',
    this.hasCompletedTutorial = false,
    this.playerShowPronunciation = true,
    this.playerShowTranslation = true,
  });

  AppSettings copyWith({
    MetadataSeparators? metadataSeparators,
    bool? musicHaptics,
    double? musicHapticsSensitivity,
    double? musicHapticsStrength,
    bool? playbackNormalization,
    double? playbackNormalizationPreamp,
    String? playbackNormalizationMode,
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

    String? libraryFilterMode,
    bool? enableLogging,
    bool? heroAnimationsEnabled,
    bool? animatedAlbumArtwork,
    bool? checkForUpdates,
    String? updateChannel,
    bool? developerOptionsUnlocked,
    bool? performanceHudEnabled,
    bool? barSamplerDisabled,
    bool? headerBandBlurDisabled,
    String? glassQuality,
    int? glassClarityLevel,
    String? locale,
    bool? keepScreenOnLyrics,
    bool? listeningStatisticsEnabled,
    bool? localLibraryShowDuplicates,
    String? localLibraryAutoScan,
    bool? hasCompletedTutorial,
    bool? playerShowPronunciation,
    bool? playerShowTranslation,
  }) {
    return AppSettings(
      metadataSeparators: metadataSeparators ?? this.metadataSeparators,
      musicHaptics: musicHaptics ?? this.musicHaptics,
      musicHapticsSensitivity:
          musicHapticsSensitivity ?? this.musicHapticsSensitivity,
      musicHapticsStrength: musicHapticsStrength ?? this.musicHapticsStrength,
      playbackNormalization:
          playbackNormalization ?? this.playbackNormalization,
      playbackNormalizationPreamp:
          playbackNormalizationPreamp ?? this.playbackNormalizationPreamp,
      playbackNormalizationMode:
          playbackNormalizationMode ?? this.playbackNormalizationMode,
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

      libraryFilterMode: libraryFilterMode ?? this.libraryFilterMode,
      enableLogging: enableLogging ?? this.enableLogging,
      heroAnimationsEnabled:
          heroAnimationsEnabled ?? this.heroAnimationsEnabled,
      animatedAlbumArtwork: animatedAlbumArtwork ?? this.animatedAlbumArtwork,
      checkForUpdates: checkForUpdates ?? this.checkForUpdates,
      updateChannel: updateChannel ?? this.updateChannel,
      developerOptionsUnlocked:
          developerOptionsUnlocked ?? this.developerOptionsUnlocked,
      performanceHudEnabled:
          performanceHudEnabled ?? this.performanceHudEnabled,
      barSamplerDisabled: barSamplerDisabled ?? this.barSamplerDisabled,
      headerBandBlurDisabled:
          headerBandBlurDisabled ?? this.headerBandBlurDisabled,
      glassQuality: glassQuality ?? this.glassQuality,
      glassClarityLevel: glassClarityLevel ?? this.glassClarityLevel,
      locale: locale ?? this.locale,
      keepScreenOnLyrics: keepScreenOnLyrics ?? this.keepScreenOnLyrics,
      listeningStatisticsEnabled:
          listeningStatisticsEnabled ?? this.listeningStatisticsEnabled,
      localLibraryShowDuplicates:
          localLibraryShowDuplicates ?? this.localLibraryShowDuplicates,
      localLibraryAutoScan: localLibraryAutoScan ?? this.localLibraryAutoScan,
      hasCompletedTutorial: hasCompletedTutorial ?? this.hasCompletedTutorial,
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
