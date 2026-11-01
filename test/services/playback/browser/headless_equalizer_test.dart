import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/core/models/equalizer_settings.dart';
import 'package:sistrum/services/playback/audio/playback_equalizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'headless bootstrap reads the phone EQ without rewriting the preset store',
    () async {
      const settings = EqualizerSettings(enabled: true);
      final raw = jsonEncode({
        'settings': settings.toJson(),
        'presets': <Object?>[],
      });
      SharedPreferences.setMockInitialValues({
        kPlaybackEqualizerStorageKey: raw,
      });
      final prefs = await SharedPreferences.getInstance();
      expect(loadBootstrapEqualizer(prefs).enabled, true);
      expect(prefs.getString(kPlaybackEqualizerStorageKey), raw);
    },
  );
  test(
    'corrupted saved EQ is neutral and left available for UI recovery',
    () async {
      SharedPreferences.setMockInitialValues({
        kPlaybackEqualizerStorageKey: 'bad json',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(loadBootstrapEqualizer(prefs).enabled, false);
      expect(prefs.getString(kPlaybackEqualizerStorageKey), 'bad json');
    },
  );
}
