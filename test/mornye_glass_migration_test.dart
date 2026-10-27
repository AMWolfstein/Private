import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/models/mornye_glass.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/services/mornye_glass_migration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const auto = MornyeGlassQuality.auto;
  const full = MornyeGlassQuality.full;
  const off = MornyeGlassQuality.off;

  // (old clarity, forceBackdropBlur) -> (quality, level)
  final rows = <(double?, bool?, MornyeGlassQuality, int)>[
    (0.0, null, off, 3),
    (0.2, false, off, 3),
    // Opaque clarity wins over a forced blur.
    (0.2, true, off, 3),
    (0.21, null, auto, 1),
    (0.35, null, auto, 1),
    (0.36, null, auto, 2),
    (0.55, null, auto, 2),
    (0.56, null, auto, 3),
    (0.7, null, auto, 3),
    (0.71, null, auto, 4),
    (0.75, false, auto, 4),
    (0.89, null, auto, 4),
    (0.9, null, auto, 5),
    (1.0, null, auto, 5),
    (0.75, true, full, 4),
    // Settings without a saved clarity keep the default level.
    (null, true, full, 3),
    (null, false, auto, 3),
  ];

  test('every legacy clarity and blur combination maps to quality + level', () {
    for (final (clarity, force, quality, level) in rows) {
      final mapped = mapLegacyGlassPreferences(
        clarity: clarity,
        forceBackdropBlur: force,
      );
      expect(
        (mapped.quality, mapped.level),
        (quality, level),
        reason: 'clarity $clarity, force $force',
      );
    }
  });

  Map<String, dynamic> blob(SharedPreferences prefs) =>
      jsonDecode(prefs.getString('app_settings')!) as Map<String, dynamic>;

  test('startup migration writes the new keys and deletes the old', () async {
    for (final (clarity, force, quality, level) in rows) {
      SharedPreferences.setMockInitialValues({
        kLegacyGlassClarityKey: ?clarity,
        'app_settings': jsonEncode({
          'locale': 'ar',
          kLegacyForceBackdropBlurKey: ?force,
          if (force == null) 'isFirstLaunch': false,
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      await migrateLegacyGlassPreferences(prefs);
      final saved = blob(prefs);
      expect(saved['glassQuality'], quality.name);
      expect(saved['glassClarityLevel'], level);
      expect(saved['locale'], 'ar', reason: 'other settings survive');
      expect(saved.containsKey(kLegacyForceBackdropBlurKey), isFalse);
      expect(prefs.containsKey(kLegacyGlassClarityKey), isFalse);
      final settings = loadBootstrapSettings(prefs);
      expect(settings.glassQuality, quality.name);
      expect(settings.glassClarityLevel, level);
    }
  });

  test('a clarity saved before any app settings still migrates', () async {
    SharedPreferences.setMockInitialValues({kLegacyGlassClarityKey: 0.95});
    final prefs = await SharedPreferences.getInstance();
    await migrateLegacyGlassPreferences(prefs);
    expect(blob(prefs)['glassClarityLevel'], 5);
    expect(blob(prefs)['glassQuality'], 'auto');
    expect(prefs.containsKey(kLegacyGlassClarityKey), isFalse);
  });

  test('a new install gets auto and level 3 without writing', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await migrateLegacyGlassPreferences(prefs);
    expect(prefs.getKeys(), isEmpty);
    final settings = loadBootstrapSettings(prefs);
    expect(settings.glassQuality, 'auto');
    expect(settings.glassClarityLevel, 3);
  });

  test('migration runs once: new keys are kept, leftovers removed', () async {
    SharedPreferences.setMockInitialValues({
      kLegacyGlassClarityKey: 0.1,
      'app_settings': jsonEncode({
        'glassQuality': 'lite',
        'glassClarityLevel': 2,
        kLegacyForceBackdropBlurKey: true,
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    await migrateLegacyGlassPreferences(prefs);
    expect(blob(prefs)['glassQuality'], 'lite');
    expect(blob(prefs)['glassClarityLevel'], 2);
    expect(blob(prefs).containsKey(kLegacyForceBackdropBlurKey), isFalse);
    expect(prefs.containsKey(kLegacyGlassClarityKey), isFalse);
    final before = prefs.getString('app_settings');
    await migrateLegacyGlassPreferences(prefs);
    expect(prefs.getString('app_settings'), before);
  });

  test('an unreadable settings blob is left for the corrupt backup', () async {
    SharedPreferences.setMockInitialValues({
      kLegacyGlassClarityKey: 0.5,
      'app_settings': '{not json',
    });
    final prefs = await SharedPreferences.getInstance();
    await migrateLegacyGlassPreferences(prefs);
    expect(prefs.getString('app_settings'), '{not json');
  });

  test('old backups restore through the same mapping', () async {
    for (final (clarity, force, quality, level) in rows) {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(settingsProvider.notifier);
      await notifier.ensureLoaded();
      final backup = const AppSettings(locale: 'de').toJson()
        ..remove('glassQuality')
        ..remove('glassClarityLevel')
        ..[kLegacyForceBackdropBlurKey] = force;
      if (clarity != null) backup[kLegacyGlassClarityKey] = clarity;
      await notifier.restoreFromBackup(backup);
      final restored = container.read(settingsProvider);
      expect(
        (restored.glassQuality, restored.glassClarityLevel),
        (quality.name, level),
        reason: 'clarity $clarity, force $force',
      );
      expect(restored.locale, 'de');
    }
  });

  test('new backups carry only the new keys and restore as is', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(settingsProvider.notifier);
    await notifier.ensureLoaded();
    final backup = const AppSettings(
      glassQuality: 'lite',
      glassClarityLevel: 5,
    ).toJson();
    expect(backup.containsKey(kLegacyForceBackdropBlurKey), isFalse);
    expect(backup.containsKey(kLegacyGlassClarityKey), isFalse);
    expect(backup['glassQuality'], 'lite');
    expect(backup['glassClarityLevel'], 5);
    await notifier.restoreFromBackup(backup);
    expect(container.read(settingsProvider).glassQuality, 'lite');
    expect(container.read(settingsProvider).glassClarityLevel, 5);
  });
}
