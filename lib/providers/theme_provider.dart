import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/models/theme_settings.dart';

final initialThemeSettingsProvider = Provider<ThemeSettings>(
  (ref) => const ThemeSettings(),
);

ThemeSettings loadBootstrapThemeSettings(SharedPreferences prefs) {
  return ThemeSettings(
    themeMode: themeModeFromString(prefs.getString(kThemeModeKey)),
    playerView: playerViewFromString(prefs.getString(kPlayerViewKey)),
    appAccent: appAccentFromString(prefs.getString(kAppAccentKey)),
    useSystemFont: prefs.getBool(kUseSystemFontKey) ?? false,
    customFontId: prefs.getString(kCustomFontIdKey) ?? '',
    customFontName: prefs.getString(kCustomFontNameKey) ?? '',
    lyricsTextScale: normalizeLyricsTextScale(
      prefs.getDouble(kLyricsTextScaleKey),
    ),
    appGlassOutlines: prefs.getBool(kAppGlassOutlinesKey) ?? true,
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
      await prefs.setString(kPlayerViewKey, snapshot.playerView.name);
      await prefs.setString(kAppAccentKey, snapshot.appAccent.name);
      await prefs.setBool(kUseSystemFontKey, snapshot.useSystemFont);
      await prefs.setString(kCustomFontIdKey, snapshot.customFontId);
      await prefs.setString(kCustomFontNameKey, snapshot.customFontName);
      await prefs.setDouble(kLyricsTextScaleKey, snapshot.lyricsTextScale);
      await prefs.setBool(
        kAppGlassOutlinesKey,
        snapshot.appGlassOutlines,
      );
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

  Future<void> setAppAccent(AppAccent accent) async {
    _editState((current) => current.copyWith(appAccent: accent));
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

  Future<void> setAppGlassOutlines(bool value) async {
    _editState((current) => current.copyWith(appGlassOutlines: value));
    await _saveToStorage();
  }
}
