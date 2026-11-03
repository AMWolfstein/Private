import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/core/models/theme_settings.dart';
import 'package:sistrum/services/platform/retired_appearance_cleanup.dart';

final initialThemeSettingsProvider = Provider<ThemeSettings>(
  (ref) => const ThemeSettings(),
);

ThemeSettings loadBootstrapThemeSettings(SharedPreferences prefs) {
  return ThemeSettings(
    themeMode: themeModeFromString(prefs.getString(kThemeModeKey)),
    playerView: playerViewFromString(prefs.getString(kPlayerViewKey)),
    lyricsTextScale: normalizeLyricsTextScale(
      prefs.getDouble(kLyricsTextScaleKey),
    ),
    lyricsTimingOffsetMs: normalizeLyricsTimingOffset(
      prefs.getInt(kLyricsTimingOffsetKey),
    ),
    lyricsBlur: normalizeLyricsBlur(
      prefs.get(kLyricsBlurKey) is num
          ? prefs.get(kLyricsBlurKey) as num
          : null,
    ),
  );
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeSettings>(() {
  return ThemeNotifier();
});

class ThemeNotifier extends Notifier<ThemeSettings> {
  ThemeNotifier({Future<SharedPreferences>? preferences})
    : _prefs = preferences ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefs;
  late Future<void> _loadFuture;
  Future<void> _saveChain = Future<void>.value();
  final _loadingEdits = <ThemeSettings Function(ThemeSettings)>[];
  bool _loaded = false;

  @override
  ThemeSettings build() {
    _loadFuture = _loadFromStorage();
    return ref.read(initialThemeSettingsProvider);
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await _prefs;
      var loaded = loadBootstrapThemeSettings(prefs);
      if (prefs.containsKey('custom_font_id')) {
        await deleteRetiredFontCacheBestEffort();
      }
      await _removeRetiredAppearancePreferences(prefs);
      for (final edit in _loadingEdits) {
        loaded = edit(loaded);
      }
      if (ref.mounted) state = loaded;
    } catch (e) {
      debugPrint('Error loading theme settings: $e');
    } finally {
      _loaded = true;
      _loadingEdits.clear();
    }
  }

  void _editState(ThemeSettings Function(ThemeSettings) edit) {
    if (!_loaded) _loadingEdits.add(edit);
    state = edit(state);
  }

  Future<void> _saveToStorage() => _saveChain = _saveChain.then((_) async {
    try {
      await _loadFuture;
      final prefs = await _prefs;
      if (!ref.mounted) return;
      final snapshot = state;
      await prefs.setString(kThemeModeKey, snapshot.themeMode.name);
      await prefs.setString(kPlayerViewKey, snapshot.playerView.name);
      await prefs.setDouble(kLyricsTextScaleKey, snapshot.lyricsTextScale);
      await prefs.setDouble(kLyricsBlurKey, snapshot.lyricsBlur);
      await prefs.setInt(kLyricsTimingOffsetKey, snapshot.lyricsTimingOffsetMs);
    } catch (e) {
      debugPrint('Error saving theme settings: $e');
    }
  });

  Future<void> setPlayerView(PlayerView view) async {
    _editState((current) => current.copyWith(playerView: view));
    await _saveToStorage();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _editState((current) => current.copyWith(themeMode: mode));
    await _saveToStorage();
  }

  Future<void> setLyricsTextScale(double value, {bool persist = true}) async {
    _editState((current) => current.copyWith(lyricsTextScale: value));
    if (persist) await _saveToStorage();
  }

  Future<void> setLyricsBlur(double value, {bool persist = true}) async {
    _editState((current) => current.copyWith(lyricsBlur: value));
    if (persist) await _saveToStorage();
  }

  Future<void> setLyricsTimingOffset(int value, {bool persist = true}) async {
    _editState((current) => current.copyWith(lyricsTimingOffsetMs: value));
    if (persist) await _saveToStorage();
  }
}

/// Retired values are ignored at bootstrap and stripped on the next load/save.
Future<void> _removeRetiredAppearancePreferences(
  SharedPreferences prefs,
) async {
  for (final key in const [
    'sistrum_accent',
    'use_system_font',
    'custom_font_id',
    'custom_font_name',
    'sistrum_glass_outlines',
  ]) {
    await prefs.remove(key);
  }
}
