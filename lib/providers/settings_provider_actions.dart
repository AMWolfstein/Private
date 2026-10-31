part of 'settings_provider.dart';

extension SettingsActions on SettingsNotifier {
  /// Restores portable preferences while retaining this installation's setup
  /// completion and selected local-library source.
  Future<void> restoreFromBackup(Map<String, dynamic> json) async {
    await ensureLoaded();
    final current = _current;
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
    _current = candidate;
    try {
      await _saveSettings(throwOnFailure: true);
    } catch (_) {
      if (identical(_current, candidate)) _current = current;
      rethrow;
    }
  }

  void setPlaybackNormalization(bool enabled) {
    _current = _current.copyWith(playbackNormalization: enabled);
    _saveSettings();
  }

  void setPlaybackNormalizationPreamp(double db) {
    _current = _current.copyWith(
      playbackNormalizationPreamp: playbackNormalizationPreampFromJson(db),
    );
    _saveSettings();
  }

  void setPlaybackNormalizationMode(String mode) {
    _current = _current.copyWith(
      playbackNormalizationMode: playbackNormalizationModeFromJson(mode),
    );
    _saveSettings();
  }

  void setMusicHaptics(bool enabled) {
    _current = _current.copyWith(musicHaptics: enabled);
    _saveSettings();
  }

  void setMusicHapticsSensitivity(double value) {
    _current = _current.copyWith(
      musicHapticsSensitivity: musicHapticsLevelFromJson(value),
    );
    _saveSettings();
  }

  void setMusicHapticsStrength(double value) {
    _current = _current.copyWith(
      musicHapticsStrength: musicHapticsLevelFromJson(value),
    );
    _saveSettings();
  }

  void setPauseOnMute(bool enabled) {
    _current = _current.copyWith(pauseOnMute: enabled);
    _saveSettings();
  }

  void setPlayOnHeadphonesConnected(bool enabled) {
    _current = _current.copyWith(playOnHeadphonesConnected: enabled);
    _saveSettings();
  }

  void setAutoMixDuration(int seconds) {
    _current = _current.copyWith(
      autoMixDuration: autoMixDurationFromJson(seconds),
    );
    _saveSettings();
  }

  void setAutoMixEffect(AutoMixEffect effect) {
    _current = _current.copyWith(
      autoMixEffect: effect,
      autoMixPitch: effect == AutoMixEffect.pitch && _current.autoMixPitch == 0
          ? 2
          : _current.autoMixPitch,
    );
    _saveSettings();
  }

  void setAutoMixSpeed(double speed) {
    _current = _current.copyWith(autoMixSpeed: autoMixSpeedFromJson(speed));
    _saveSettings();
  }

  void setAutoMixPitch(double semitones) {
    _current = _current.copyWith(autoMixPitch: autoMixPitchFromJson(semitones));
    _saveSettings();
  }

  void setAutoMixEcho(bool enabled) {
    _current = _current.copyWith(autoMixEcho: enabled);
    _saveSettings();
  }

  void setAutoMixLowPass(bool enabled) {
    _current = _current.copyWith(autoMixLowPass: enabled);
    _saveSettings();
  }

  void setAutoplayPersonalization(bool enabled) {
    _current = _current.copyWith(autoplayPersonalization: enabled);
    _saveSettings();
  }

  void setUsbBitPerfect(bool enabled) {
    _current = _current.copyWith(usbBitPerfect: enabled);
    _saveSettings();
  }

  void setUsbDirect(bool enabled) {
    _current = _current.copyWith(
      usbDirect: enabled,
      dapExclusive: enabled ? false : null,
    );
    _saveSettings();
  }

  void setUsbDsdOverPcm(bool enabled) {
    _current = _current.copyWith(usbDsdOverPcm: enabled);
    _saveSettings();
  }

  void setUsbAllowFixedVolume(bool enabled) {
    _current = _current.copyWith(usbAllowFixedVolume: enabled);
    _saveSettings();
  }

  void setDapExclusive(bool enabled) {
    _current = _current.copyWith(
      dapExclusive: enabled,
      usbDirect: enabled ? false : null,
    );
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
        final completed = _current.copyWith(
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
        if (!_saveQueued && _ref.mounted) _current = completed;
      } while (_saveQueued);
    } finally {
      _saveSettingsFuture = null;
      saved.complete();
    }
  }

  void setHeroAnimationsEnabled(bool enabled) {
    _current = _current.copyWith(heroAnimationsEnabled: enabled);
    _saveSettings();
  }

  void setAnimatedAlbumArtwork(bool enabled) {
    _current = _current.copyWith(animatedAlbumArtwork: enabled);
    _saveSettings();
  }

  void setLyricsAboveSeekBar(bool enabled) {
    _current = _current.copyWith(lyricsAboveSeekBar: enabled);
    _saveSettings();
  }

  void setCheckForUpdates(bool enabled) {
    _current = _current.copyWith(checkForUpdates: enabled);
    _saveSettings();
  }

  void setUpdateChannel(String channel) {
    _current = _current.copyWith(
      updateChannel: channel == 'preview' ? 'preview' : 'stable',
    );
    _saveSettings();
  }

  void setDeveloperOptionsUnlocked(bool unlocked) {
    _current = _current.copyWith(
      developerOptionsUnlocked: unlocked,
      // Hiding the options also removes the overlay and A/B switches they
      // control.
      performanceHudEnabled: unlocked && _current.performanceHudEnabled,
      barSamplerDisabled: unlocked && _current.barSamplerDisabled,
      headerBandBlurDisabled: unlocked && _current.headerBandBlurDisabled,
    );
    _saveSettings();
  }

  void setPerformanceHudEnabled(bool enabled) {
    _current = _current.copyWith(performanceHudEnabled: enabled);
    _saveSettings();
  }

  void setBarSamplerDisabled(bool disabled) {
    _current = _current.copyWith(barSamplerDisabled: disabled);
    _saveSettings();
  }

  void setHeaderBandBlurDisabled(bool disabled) {
    _current = _current.copyWith(headerBandBlurDisabled: disabled);
    _saveSettings();
  }

  void setLocale(String locale) {
    _current = _current.copyWith(locale: locale);
    _saveSettings();
  }

  void setLocalLibraryShowDuplicates(bool show) {
    _current = _current.copyWith(localLibraryShowDuplicates: show);
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
    final current = _current.tagCredits;
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
    final current = _current.tagCredits;
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
    final existing = _current.tagCredits.keepTogether;
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
    _current = _current.copyWith(localLibraryAutoScan: mode);
    _saveSettings();
  }

  void setPlayerShowPronunciation(bool visible) {
    _current = _current.copyWith(playerShowPronunciation: visible);
    _saveSettings();
  }

  void setPlayerShowTranslation(bool visible) {
    _current = _current.copyWith(playerShowTranslation: visible);
    _saveSettings();
  }
}
