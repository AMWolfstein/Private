import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/models/mornye_glass.dart';

const _settingsKey = 'app_settings';

/// Moves the retired clarity double (theme preferences) and the
/// "Always use blur effects" flag (app settings JSON) to `glassQuality` and
/// `glassClarityLevel`, then deletes the old keys. Runs at every startup
/// before settings are read; it only writes when old keys are present.
Future<void> migrateLegacyGlassPreferences(SharedPreferences prefs) async {
  final clarity = prefs.get(kLegacyGlassClarityKey);
  Map<String, dynamic>? settings;
  final raw = prefs.getString(_settingsKey);
  if (raw != null && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) settings = Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  // Leave an unreadable blob for the settings notifier's corrupt backup.
  if (raw != null && raw.isNotEmpty && settings == null) return;
  final hasForce = settings?.containsKey(kLegacyForceBackdropBlurKey) ?? false;
  if (clarity == null && !hasForce) return;

  if (!(settings?.containsKey('glassQuality') ?? false)) {
    final mapped = mapLegacyGlassPreferences(
      clarity: clarity is num ? clarity : null,
      forceBackdropBlur: settings?[kLegacyForceBackdropBlurKey] as bool?,
    );
    settings ??= <String, dynamic>{};
    settings['glassQuality'] = mapped.quality.name;
    settings['glassClarityLevel'] = mapped.level;
  }
  if (settings != null) {
    settings.remove(kLegacyForceBackdropBlurKey);
    await prefs.setString(_settingsKey, jsonEncode(settings));
  }
  await prefs.remove(kLegacyGlassClarityKey);
}
