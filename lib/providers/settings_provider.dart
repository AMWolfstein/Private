import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/core/models/app_glass.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/core/models/metadata_separators.dart';
import 'package:sistrum/core/models/tag_credit_settings.dart';
import 'package:sistrum/core/models/automix_options.dart';
import 'package:sistrum/utils/logging/logger.dart';

const _settingsKey = 'app_settings';
const _settingsCorruptBackupKey = 'app_settings_corrupt_backup';
final _log = AppLogger('SettingsProvider');

/// Startup override used to render the correct route/locale on the first
/// frame. The notifier still performs migrations and full validation after it
/// mounts.
final initialSettingsProvider = Provider<AppSettings>(
  (ref) => const AppSettings(),
);

bool hasPersistedAppSettings(SharedPreferences prefs) {
  final rawSettings = prefs.getString(_settingsKey);
  return rawSettings != null && rawSettings.isNotEmpty;
}

AppSettings loadBootstrapSettings(SharedPreferences prefs) {
  final rawSettings = prefs.getString(_settingsKey);
  if (rawSettings == null || rawSettings.isEmpty) return const AppSettings();
  try {
    final decoded = jsonDecode(rawSettings);
    if (decoded is! Map) return const AppSettings();
    final settings = AppSettings.fromJson(Map<String, dynamic>.from(decoded));
    return !settings.isFirstLaunch && !settings.hasCompletedTutorial
        ? settings.copyWith(hasCompletedTutorial: true)
        : settings;
  } catch (_) {
    return const AppSettings();
  }
}

/// Removes values that are only valid for one OS installation while keeping
/// portable user preferences. This is used when Android restores app data into
/// a fresh package install despite backup being disabled (for example an OEM
/// device-to-device transfer).
AppSettings resetInstallationBoundSettings(AppSettings settings) {
  return settings.copyWith(
    isFirstLaunch: true,
    localLibraryAutoScan: 'off',
    hasCompletedTutorial: false,
  );
}

Future<void> resetRestoredInstallationSettings(SharedPreferences prefs) async {
  final rawSettings = prefs.getString(_settingsKey);
  if (rawSettings == null || rawSettings.isEmpty) return;

  try {
    final decoded = jsonDecode(rawSettings);
    if (decoded is! Map) {
      await prefs.remove(_settingsKey);
      return;
    }
    final restored = AppSettings.fromJson(Map<String, dynamic>.from(decoded));
    final sanitized = resetInstallationBoundSettings(restored);
    await prefs.setString(_settingsKey, jsonEncode(sanitized.toJson()));
  } catch (e) {
    _log.w('Failed to sanitize restored settings; resetting to defaults: $e');
    await prefs.remove(_settingsKey);
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  SettingsNotifier({Future<SharedPreferences> Function()? preferences})
    : _loadPreferences = preferences ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _loadPreferences;
  Future<SharedPreferences> get _prefs => _loadPreferences();
  Future<void>? _saveSettingsFuture;
  bool _saveQueued = false;
  String? _pendingSettingsJson;
  Future<void>? _loadSettingsFuture;

  @override
  AppSettings build() {
    unawaited(
      ensureLoaded().catchError((Object error, StackTrace stack) {
        _log.e('Failed to load settings', error, stack);
      }),
    );
    return ref.read(initialSettingsProvider);
  }

  /// Startup actions share loading, including preference migrations.
  Future<void> ensureLoaded() {
    return _loadSettingsFuture ??= _loadSettings().catchError((
      Object error,
      StackTrace stack,
    ) {
      _loadSettingsFuture = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await _prefs;
    final rawSettings = prefs.getString(_settingsKey);
    if (rawSettings != null) {
      AppSettings? loaded;
      try {
        final decoded = jsonDecode(rawSettings);
        if (decoded is! Map) {
          throw const FormatException('settings root must be a JSON object');
        }
        loaded = AppSettings.fromJson(Map<String, dynamic>.from(decoded));
      } catch (e, stack) {
        _log.e('Failed to load settings, resetting to defaults: $e', e, stack);
        try {
          await prefs.setString(_settingsCorruptBackupKey, rawSettings);
          await prefs.remove(_settingsKey);
        } catch (backupError) {
          _log.w('Failed to backup corrupt settings: $backupError');
        }
      }

      if (loaded != null) {
        state = !loaded.isFirstLaunch && !loaded.hasCompletedTutorial
            ? loaded.copyWith(hasCompletedTutorial: true)
            : loaded;
      }
    }
  }

  Future<void> _saveSettings({bool throwOnFailure = false}) {
    _pendingSettingsJson = jsonEncode(state.toJson());

    final activeSave = _saveSettingsFuture;
    if (activeSave != null) {
      _saveQueued = true;
      return throwOnFailure ? activeSave : activeSave.catchError((Object _) {});
    }

    final saved = Completer<void>();
    _saveSettingsFuture = saved.future;
    unawaited(_drainSettingsSave(saved));
    return throwOnFailure
        ? saved.future
        : saved.future.catchError((Object _) {});
  }

  Future<void> _drainSettingsSave(Completer<void> saved) async {
    try {
      final prefs = await _prefs;
      do {
        final jsonToWrite = _pendingSettingsJson;
        _saveQueued = false;
        if (jsonToWrite != null) {
          if (!await prefs.setString(_settingsKey, jsonToWrite)) {
            throw StateError('Could not save settings');
          }
        }
      } while (_saveQueued);
    } catch (e, stack) {
      _log.e('Failed to save settings: $e');
      saved.completeError(e, stack);
    } finally {
      _saveSettingsFuture = null;
      if (!saved.isCompleted) saved.complete();
    }
  }

  /// Restores portable preferences while retaining this installation's setup
  /// completion and selected local-library source.
  Future<void> restoreFromBackup(Map<String, dynamic> json) async {
    await ensureLoaded();
    final current = state;
    AppSettings restored;
    try {
      restored = AppSettings.fromJson(Map<String, dynamic>.from(json));
    } catch (e, stack) {
      _log.e('Failed to parse settings from backup: $e', e, stack);
      rethrow;
    }
    final candidate = restored.copyWith(
      isFirstLaunch: current.isFirstLaunch,
      hasCompletedTutorial: current.hasCompletedTutorial,
      localLibraryAutoScan: current.localLibraryAutoScan,
    );
    state = candidate;
    try {
      await _saveSettings(throwOnFailure: true);
    } catch (_) {
      if (identical(state, candidate)) state = current;
      rethrow;
    }
  }

  void setPlaybackNormalization(bool enabled) {
    state = state.copyWith(playbackNormalization: enabled);
    _saveSettings();
  }

  void setPlaybackNormalizationPreamp(double db) {
    state = state.copyWith(
      playbackNormalizationPreamp: playbackNormalizationPreampFromJson(db),
    );
    _saveSettings();
  }

  void setPlaybackNormalizationMode(String mode) {
    state = state.copyWith(
      playbackNormalizationMode: playbackNormalizationModeFromJson(mode),
    );
    _saveSettings();
  }

  void setMusicHaptics(bool enabled) {
    state = state.copyWith(musicHaptics: enabled);
    _saveSettings();
  }

  void setMusicHapticsSensitivity(double value) {
    state = state.copyWith(
      musicHapticsSensitivity: musicHapticsLevelFromJson(value),
    );
    _saveSettings();
  }

  void setMusicHapticsStrength(double value) {
    state = state.copyWith(
      musicHapticsStrength: musicHapticsLevelFromJson(value),
    );
    _saveSettings();
  }

  void setPauseOnMute(bool enabled) {
    state = state.copyWith(pauseOnMute: enabled);
    _saveSettings();
  }

  void setPlayOnHeadphonesConnected(bool enabled) {
    state = state.copyWith(playOnHeadphonesConnected: enabled);
    _saveSettings();
  }

  void setAutoMix(bool enabled) {
    state = state.copyWith(autoMix: enabled);
    _saveSettings();
  }

  void setAutoMixDuration(int seconds) {
    state = state.copyWith(autoMixDuration: autoMixDurationFromJson(seconds));
    _saveSettings();
  }

  void setAutoMixEffect(AutoMixEffect effect) {
    state = state.copyWith(
      autoMixEffect: effect,
      autoMixPitch: effect == AutoMixEffect.pitch && state.autoMixPitch == 0
          ? 2
          : state.autoMixPitch,
    );
    _saveSettings();
  }

  void setAutoMixSpeed(double speed) {
    state = state.copyWith(autoMixSpeed: autoMixSpeedFromJson(speed));
    _saveSettings();
  }

  void setAutoMixPitch(double semitones) {
    state = state.copyWith(autoMixPitch: autoMixPitchFromJson(semitones));
    _saveSettings();
  }

  void setAutoMixEcho(bool enabled) {
    state = state.copyWith(autoMixEcho: enabled);
    _saveSettings();
  }

  void setAutoMixLowPass(bool enabled) {
    state = state.copyWith(autoMixLowPass: enabled);
    _saveSettings();
  }

  void setAutoplay(bool enabled) {
    state = state.copyWith(autoplay: enabled);
    _saveSettings();
  }

  void setAutoplayPersonalization(bool enabled) {
    state = state.copyWith(autoplayPersonalization: enabled);
    _saveSettings();
  }

  void setUsbBitPerfect(bool enabled) {
    state = state.copyWith(usbBitPerfect: enabled);
    _saveSettings();
  }

  void setUsbDirect(bool enabled) {
    state = state.copyWith(
      usbDirect: enabled,
      dapExclusive: enabled ? false : null,
    );
    _saveSettings();
  }

  void setUsbDsdOverPcm(bool enabled) {
    state = state.copyWith(usbDsdOverPcm: enabled);
    _saveSettings();
  }

  void setUsbAllowFixedVolume(bool enabled) {
    state = state.copyWith(usbAllowFixedVolume: enabled);
    _saveSettings();
  }

  void setDapExclusive(bool enabled) {
    state = state.copyWith(
      dapExclusive: enabled,
      usbDirect: enabled ? false : null,
    );
    _saveSettings();
  }

  void setKeepScreenOnLyrics(bool enabled) {
    state = state.copyWith(keepScreenOnLyrics: enabled);
    _saveSettings();
  }

  Future<void> setFirstLaunchComplete() async {
    // The router leaves setup as soon as this flag changes. Persist the final
    // setup settings and both completion flags together before entering Home.
    await ensureLoaded();
    final prefs = await _prefs;
    while (_saveSettingsFuture != null) {
      await _saveSettingsFuture;
    }
    final saved = Completer<void>();
    _saveSettingsFuture = saved.future;
    try {
      do {
        _saveQueued = false;
        final completed = state.copyWith(
          isFirstLaunch: false,
          hasCompletedTutorial: true,
        );
        if (!await prefs.setString(
          _settingsKey,
          jsonEncode(completed.toJson()),
        )) {
          throw StateError('Could not save completed setup');
        }
        // Include settings changed during the write before publishing the flag.
        if (!_saveQueued && ref.mounted) state = completed;
      } while (_saveQueued);
    } finally {
      _saveSettingsFuture = null;
      saved.complete();
    }
  }

  void setHeroAnimationsEnabled(bool enabled) {
    state = state.copyWith(heroAnimationsEnabled: enabled);
    _saveSettings();
  }

  void setAnimatedAlbumArtwork(bool enabled) {
    state = state.copyWith(animatedAlbumArtwork: enabled);
    _saveSettings();
  }

  void setLyricsAboveSeekBar(bool enabled) {
    state = state.copyWith(lyricsAboveSeekBar: enabled);
    _saveSettings();
  }

  void setCheckForUpdates(bool enabled) {
    state = state.copyWith(checkForUpdates: enabled);
    _saveSettings();
  }

  void setUpdateChannel(String channel) {
    state = state.copyWith(
      updateChannel: channel == 'preview' ? 'preview' : 'stable',
    );
    _saveSettings();
  }

  void setDeveloperOptionsUnlocked(bool unlocked) {
    state = state.copyWith(
      developerOptionsUnlocked: unlocked,
      // Hiding the options also removes the overlay and A/B switches they
      // control.
      performanceHudEnabled: unlocked && state.performanceHudEnabled,
      barSamplerDisabled: unlocked && state.barSamplerDisabled,
      headerBandBlurDisabled: unlocked && state.headerBandBlurDisabled,
    );
    _saveSettings();
  }

  void setPerformanceHudEnabled(bool enabled) {
    state = state.copyWith(performanceHudEnabled: enabled);
    _saveSettings();
  }

  void setBarSamplerDisabled(bool disabled) {
    state = state.copyWith(barSamplerDisabled: disabled);
    _saveSettings();
  }

  void setHeaderBandBlurDisabled(bool disabled) {
    state = state.copyWith(headerBandBlurDisabled: disabled);
    _saveSettings();
  }

  void setGlassQuality(AppGlassQuality quality) {
    state = state.copyWith(glassQuality: quality.name);
    _saveSettings();
  }

  /// [persist] false updates the app without writing preferences.
  Future<void> setGlassClarityLevel(int level, {bool persist = true}) async {
    state = state.copyWith(glassClarityLevel: level.clamp(1, 5));
    if (persist) await _saveSettings();
  }

  void setLocale(String locale) {
    state = state.copyWith(locale: locale);
    _saveSettings();
  }

  void setLocalLibraryShowDuplicates(bool show) {
    state = state.copyWith(localLibraryShowDuplicates: show);
    _saveSettings();
  }

  void setMetadataSeparator(String field, String separator) {
    if (!MetadataSeparators.fields.contains(field) ||
        MetadataSeparators.validSeparator(separator) != separator) {
      return;
    }
    state = state.copyWith(
      metadataSeparators: state.metadataSeparators.withField(field, separator),
    );
    _saveSettings();
  }

  /// Save-time separator shared by artist, album artist and composer.
  void setMetadataNamesSeparator(String separator) {
    if (MetadataSeparators.validSeparator(separator) != separator) return;
    state = state.copyWith(
      metadataSeparators: state.metadataSeparators.withNames(separator),
    );
    _saveSettings();
  }

  void toggleArtistDelimiter(String token) => _updateTagCredits(
    (c) => c.copyWith(
      artistDelimiters: _toggledDelimiter(c.artistDelimiters, token),
    ),
  );

  void toggleGenreDelimiter(String token) => _updateTagCredits(
    (c) => c.copyWith(
      genreDelimiters: _toggledDelimiter(c.genreDelimiters, token),
    ),
  );

  /// Selects every offered artist delimiter; when all are already selected,
  /// returns the section to its defaults.
  void toggleAllArtistDelimiters() => _updateTagCredits((c) {
    final offered = [...kArtistDelimiterChoices, ...c.customArtistDelimiters];
    final allSelected = offered.every(c.artistDelimiters.contains);
    return c.copyWith(
      artistDelimiters: allSelected ? kArtistDelimiterDefaults : offered,
    );
  });

  void toggleAllGenreDelimiters() => _updateTagCredits((c) {
    final offered = [...kGenreDelimiterChoices, ...c.customGenreDelimiters];
    final allSelected = offered.every(c.genreDelimiters.contains);
    return c.copyWith(
      genreDelimiters: allSelected ? kGenreDelimiterDefaults : offered,
    );
  });

  /// Adds a custom artist delimiter and selects it. Invalid or duplicate
  /// values are ignored.
  void addArtistDelimiter(String token) {
    final trimmed = token.trim();
    final current = state.tagCredits;
    final offered = [
      ...kArtistDelimiterChoices,
      ...current.customArtistDelimiters,
    ];
    if (!TagCreditSettings.isValidDelimiter(trimmed, offered)) return;
    _updateTagCredits(
      (c) => c.copyWith(
        customArtistDelimiters: [...c.customArtistDelimiters, trimmed],
        artistDelimiters: [...c.artistDelimiters, trimmed],
      ),
    );
  }

  void addGenreDelimiter(String token) {
    final trimmed = token.trim();
    final current = state.tagCredits;
    final offered = [
      ...kGenreDelimiterChoices,
      ...current.customGenreDelimiters,
    ];
    if (!TagCreditSettings.isValidDelimiter(trimmed, offered)) return;
    _updateTagCredits(
      (c) => c.copyWith(
        customGenreDelimiters: [...c.customGenreDelimiters, trimmed],
        genreDelimiters: [...c.genreDelimiters, trimmed],
      ),
    );
  }

  /// Removes a custom artist delimiter. When that leaves nothing selected,
  /// the section falls back to its defaults so it never splits on nothing.
  void removeCustomArtistDelimiter(String token) => _updateTagCredits((c) {
    final selected = c.artistDelimiters.where((t) => t != token).toList();
    return c.copyWith(
      customArtistDelimiters: c.customArtistDelimiters
          .where((t) => t != token)
          .toList(),
      artistDelimiters: selected.isEmpty ? kArtistDelimiterDefaults : selected,
    );
  });

  void removeCustomGenreDelimiter(String token) => _updateTagCredits((c) {
    final selected = c.genreDelimiters.where((t) => t != token).toList();
    return c.copyWith(
      customGenreDelimiters: c.customGenreDelimiters
          .where((t) => t != token)
          .toList(),
      genreDelimiters: selected.isEmpty ? kGenreDelimiterDefaults : selected,
    );
  });

  void addKeepTogether(String name) {
    final trimmed = name.trim();
    final existing = state.tagCredits.keepTogether;
    if (trimmed.isEmpty || trimmed.length > 100) return;
    if (existing.any((n) => n.toLowerCase() == trimmed.toLowerCase())) return;
    if (existing.length >= 200) return;
    _updateTagCredits(
      (c) => c.copyWith(keepTogether: [...c.keepTogether, trimmed]),
    );
  }

  void removeKeepTogether(String name) => _updateTagCredits(
    (c) => c.copyWith(
      keepTogether: c.keepTogether.where((n) => n != name).toList(),
    ),
  );

  void _updateTagCredits(TagCreditSettings Function(TagCreditSettings) change) {
    state = state.copyWith(tagCredits: change(state.tagCredits));
    _saveSettings();
  }

  /// Toggling off the last selected delimiter is ignored: a section never
  /// splits on nothing.
  static List<String> _toggledDelimiter(List<String> selected, String token) {
    if (selected.contains(token)) {
      if (selected.length == 1) return selected;
      return selected.where((t) => t != token).toList();
    }
    return [...selected, token];
  }

  void setLocalLibraryAutoScan(String mode) {
    state = state.copyWith(localLibraryAutoScan: mode);
    _saveSettings();
  }

  void setPlayerShowPronunciation(bool visible) {
    state = state.copyWith(playerShowPronunciation: visible);
    _saveSettings();
  }

  void setPlayerShowTranslation(bool visible) {
    state = state.copyWith(playerShowTranslation: visible);
    _saveSettings();
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
