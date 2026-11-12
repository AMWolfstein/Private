import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mornye/models/theme_settings.dart';

final initialThemeSettingsProvider = Provider<ThemeSettings>(
  (ref) => const ThemeSettings(),
);

/// The accent to load, moving an install off the old default once. Every
/// theme save wrote the accent, so a stored red usually only means red was
/// the default. Red picked after this stays.
AppAccent _loadAccent(SharedPreferences prefs) {
  final stored = prefs.getString(kAccentKey);
  if (prefs.getBool(kAccentMovedToBlueKey) ?? false) {
    return appAccentFromString(stored);
  }
  unawaited(prefs.setBool(kAccentMovedToBlueKey, true));
  if (stored == AppAccent.red.name) {
    unawaited(prefs.setString(kAccentKey, AppAccent.blue.name));
    return AppAccent.blue;
  }
  return appAccentFromString(stored);
}

/// The retired Glass Quality slider's stored value. Glass is fixed at Clear, so
/// the key is removed once at startup and nothing reads it any more.
const _retiredGlassClarityKey = 'mornye_glass_clarity';

ThemeSettings loadBootstrapThemeSettings(SharedPreferences prefs) {
  if (prefs.containsKey(_retiredGlassClarityKey)) {
    unawaited(prefs.remove(_retiredGlassClarityKey));
  }
  return ThemeSettings(
    themeMode: themeModeFromString(prefs.getString(kThemeModeKey)),
    accent: _loadAccent(prefs),
    useSystemFont: prefs.getBool(kUseSystemFontKey) ?? false,
    customFontId: prefs.getString(kCustomFontIdKey) ?? '',
    customFontName: prefs.getString(kCustomFontNameKey) ?? '',
    lyricsTextScale: normalizeLyricsTextScale(
      prefs.getDouble(kLyricsTextScaleKey),
    ),
    lyricsBlur: normalizeLyricsBlur(prefs.getDouble(kLyricsBlurKey)),
    lyricsOffsetMs: normalizeLyricsOffsetMs(prefs.getInt(kLyricsOffsetKey)),
    glassOutlines: prefs.getBool(kGlassOutlinesKey) ?? true,
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
      await prefs.setString(kAccentKey, snapshot.accent.name);
      await prefs.setBool(kUseSystemFontKey, snapshot.useSystemFont);
      await prefs.setString(kCustomFontIdKey, snapshot.customFontId);
      await prefs.setString(kCustomFontNameKey, snapshot.customFontName);
      await prefs.setDouble(kLyricsTextScaleKey, snapshot.lyricsTextScale);
      await prefs.setDouble(kLyricsBlurKey, snapshot.lyricsBlur);
      await prefs.setInt(kLyricsOffsetKey, snapshot.lyricsOffsetMs);
      await prefs.setBool(kGlassOutlinesKey, snapshot.glassOutlines);
    } catch (e) {
      debugPrint('Error saving theme settings: $e');
    }
  });

  Future<void> setThemeMode(ThemeMode mode) async {
    _editState((current) => current.copyWith(themeMode: mode));
    await _saveToStorage();
  }

  Future<void> setAccent(AppAccent accent) async {
    _editState((current) => current.copyWith(accent: accent));
    await _saveToStorage();
  }

  Future<void> setUseSystemFont(bool value) async {
    _editState((current) => current.copyWith(useSystemFont: value));
    await _saveToStorage();
  }

  Future<void> setCustomFont(String id, String name) async {
    _editState(
      (current) => current.copyWith(customFontId: id, customFontName: name),
    );
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

  Future<void> setLyricsOffsetMs(int value, {bool persist = true}) async {
    _editState((current) => current.copyWith(lyricsOffsetMs: value));
    if (persist) await _saveToStorage();
  }

  Future<void> setGlassOutlines(bool value) async {
    _editState((current) => current.copyWith(glassOutlines: value));
    await _saveToStorage();
  }
}
