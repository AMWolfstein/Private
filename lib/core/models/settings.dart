import 'package:json_annotation/json_annotation.dart';
import 'package:sistrum/core/models/automix_options.dart';
import 'package:sistrum/core/models/tag_credit_settings.dart';

part 'settings.g.dart';

/// Pre-amp applied on top of ReplayGain during playback, in whole dB.
/// -7 dB targets -25 LUFS from the -18 LUFS tag reference.
double playbackNormalizationPreampFromJson(Object? value) =>
    value is num && value.isFinite
    ? value.toDouble().roundToDouble().clamp(-15, 6)
    : 0;

String playbackNormalizationModeFromJson(Object? value) =>
    value == 'album' ? 'album' : 'track';

String appLocaleFromJson(Object? value) => value is String ? value : 'system';

double musicHapticsLevelFromJson(Object? value) =>
    value is num && value.isFinite ? value.toDouble().clamp(0, 1) : 0.5;

/// Whole-number Hz the app asks the display for; 0 is System Default.
/// Anything else that is not a plausible rate also reads as System Default.
int displayRefreshRateFromJson(Object? value) {
  if (value is! num || !value.isFinite) return 0;
  final hz = value.round();
  return hz > 0 && hz <= 1000 ? hz : 0;
}

@JsonSerializable(explicitToJson: true)
class AppSettings {
  final TagCreditSettings tagCredits;
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
  final bool gaplessPlayback;
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
  final bool autoplaySoundMatching;
  final bool songAnalysisOnlyWhileCharging;
  final bool replayGainAutoWrite;
  final bool replayGainOnlyWhileCharging;
  final bool isFirstLaunch;

  final String libraryFilterMode;

  /// Slow Ken Burns drift on album cover headers.
  final bool animatedAlbumArtwork;

  /// Find artist photos on Deezer in the background. Off by default.
  final bool artistImagesAutoDownload;

  /// `wifi`, `mobile` or `both`: networks automatic artist image downloads may use.
  final String artistImagesNetwork;

  /// Downloads Apple Music video artwork for albums and artists in the background.
  /// Turning it off keeps every saved video.
  final bool videoArtworkAutoDownload;

  /// `wifi`, `mobile` or `both`; unknown values mean Wi-Fi only.
  final String videoArtworkNetwork;

  /// Show the sung lyric line above the player's seek bar.
  final bool lyricsAboveSeekBar;

  /// Display refresh rate requested while the app is in front, in whole Hz.
  /// 0 leaves the choice to Android (System Default).
  @JsonKey(fromJson: displayRefreshRateFromJson)
  final int displayRefreshRate;

  /// Offer new GitHub releases at startup. Versions far behind still prompt.
  final bool checkForUpdates;

  /// `stable` or `preview` (includes pre-releases).
  final String updateChannel;

  @JsonKey(fromJson: appLocaleFromJson)
  final String locale;
  final bool keepScreenOnLyrics;

  final bool localLibraryShowDuplicates;
  final String
  localLibraryAutoScan; // Auto-scan mode: 'off', 'on_open', 'daily', 'weekly'

  final bool hasCompletedTutorial;

  final bool playerShowPronunciation;
  final bool playerShowTranslation;
  final bool playerShowVolume;

  const AppSettings({
    this.tagCredits = const TagCreditSettings(),
    this.musicHaptics = false,
    this.musicHapticsSensitivity = 0.5,
    this.musicHapticsStrength = 0.5,
    this.playbackNormalization = false,
    this.playbackNormalizationPreamp = 0,
    this.playbackNormalizationMode = 'track',
    this.pauseOnMute = true,
    this.playOnHeadphonesConnected = false,
    this.gaplessPlayback = true,
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
    this.autoplaySoundMatching = false,
    this.songAnalysisOnlyWhileCharging = true,
    this.replayGainAutoWrite = false,
    this.replayGainOnlyWhileCharging = true,
    this.isFirstLaunch = true,

    this.libraryFilterMode = 'all',
    this.animatedAlbumArtwork = true,
    this.artistImagesAutoDownload = false,
    this.artistImagesNetwork = 'wifi',
    this.videoArtworkAutoDownload = false,
    this.videoArtworkNetwork = 'wifi',
    this.lyricsAboveSeekBar = false,
    this.displayRefreshRate = 0,
    this.checkForUpdates = true,
    this.updateChannel = 'stable',
    this.locale = 'system',
    this.keepScreenOnLyrics = true,
    this.localLibraryShowDuplicates = true,
    this.localLibraryAutoScan = 'off',
    this.hasCompletedTutorial = false,
    this.playerShowPronunciation = true,
    this.playerShowTranslation = true,
    this.playerShowVolume = true,
  });

  AppSettings copyWith({
    TagCreditSettings? tagCredits,
    bool? musicHaptics,
    double? musicHapticsSensitivity,
    double? musicHapticsStrength,
    bool? playbackNormalization,
    double? playbackNormalizationPreamp,
    String? playbackNormalizationMode,
    bool? pauseOnMute,
    bool? playOnHeadphonesConnected,
    bool? gaplessPlayback,
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
    bool? autoplaySoundMatching,
    bool? songAnalysisOnlyWhileCharging,
    bool? replayGainAutoWrite,
    bool? replayGainOnlyWhileCharging,
    bool? isFirstLaunch,

    String? libraryFilterMode,
    bool? animatedAlbumArtwork,
    bool? artistImagesAutoDownload,
    String? artistImagesNetwork,
    bool? videoArtworkAutoDownload,
    String? videoArtworkNetwork,
    bool? lyricsAboveSeekBar,
    int? displayRefreshRate,
    bool? checkForUpdates,
    String? updateChannel,
    String? locale,
    bool? keepScreenOnLyrics,
    bool? localLibraryShowDuplicates,
    String? localLibraryAutoScan,
    bool? hasCompletedTutorial,
    bool? playerShowPronunciation,
    bool? playerShowTranslation,
    bool? playerShowVolume,
  }) {
    return AppSettings(
      tagCredits: tagCredits ?? this.tagCredits,
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
      gaplessPlayback: gaplessPlayback ?? this.gaplessPlayback,
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
      autoplaySoundMatching:
          autoplaySoundMatching ?? this.autoplaySoundMatching,
      songAnalysisOnlyWhileCharging:
          songAnalysisOnlyWhileCharging ?? this.songAnalysisOnlyWhileCharging,
      replayGainAutoWrite: replayGainAutoWrite ?? this.replayGainAutoWrite,
      replayGainOnlyWhileCharging:
          replayGainOnlyWhileCharging ?? this.replayGainOnlyWhileCharging,
      autoplayPersonalization:
          autoplayPersonalization ?? this.autoplayPersonalization,
      isFirstLaunch: isFirstLaunch ?? this.isFirstLaunch,

      libraryFilterMode: libraryFilterMode ?? this.libraryFilterMode,
      animatedAlbumArtwork: animatedAlbumArtwork ?? this.animatedAlbumArtwork,
      artistImagesAutoDownload:
          artistImagesAutoDownload ?? this.artistImagesAutoDownload,
      artistImagesNetwork: artistImagesNetwork ?? this.artistImagesNetwork,
      videoArtworkAutoDownload:
          videoArtworkAutoDownload ?? this.videoArtworkAutoDownload,
      videoArtworkNetwork: videoArtworkNetwork ?? this.videoArtworkNetwork,
      lyricsAboveSeekBar: lyricsAboveSeekBar ?? this.lyricsAboveSeekBar,
      displayRefreshRate: displayRefreshRate ?? this.displayRefreshRate,
      checkForUpdates: checkForUpdates ?? this.checkForUpdates,
      updateChannel: updateChannel ?? this.updateChannel,
      locale: locale ?? this.locale,
      keepScreenOnLyrics: keepScreenOnLyrics ?? this.keepScreenOnLyrics,
      localLibraryShowDuplicates:
          localLibraryShowDuplicates ?? this.localLibraryShowDuplicates,
      localLibraryAutoScan: localLibraryAutoScan ?? this.localLibraryAutoScan,
      hasCompletedTutorial: hasCompletedTutorial ?? this.hasCompletedTutorial,
      playerShowPronunciation:
          playerShowPronunciation ?? this.playerShowPronunciation,
      playerShowTranslation:
          playerShowTranslation ?? this.playerShowTranslation,
      playerShowVolume: playerShowVolume ?? this.playerShowVolume,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(json);
  Map<String, dynamic> toJson() => _$AppSettingsToJson(this);
}
