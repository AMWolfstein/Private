part of 'settings_provider.dart';

extension _SettingsHelpers on SettingsNotifier {
  Future<SharedPreferences> get _prefs => _loadPreferences();
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
        _current = !loaded.isFirstLaunch && !loaded.hasCompletedTutorial
            ? loaded.copyWith(hasCompletedTutorial: true)
            : loaded;
      }
    }
  }

  Future<void> _saveSettings({bool throwOnFailure = false}) {
    _pendingSettingsJson = jsonEncode(_current.toJson());

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

  void _updateTagCredits(TagCreditSettings Function(TagCreditSettings) change) {
    _current = _current.copyWith(tagCredits: change(_current.tagCredits));
    _saveSettings();
  }
}
