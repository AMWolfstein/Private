import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'debug-key release fallback carries an explicit distribution warning',
    () {
      // Source contract only: this does not build, sign, or validate an APK.
      final script = File('android/app/build.gradle.kts').readAsStringSync();
      final fallback = RegExp(
        r'signingConfig = if \(keystorePropertiesFile\.exists\(\)\) \{'
        r'([\s\S]*?)\} else \{([\s\S]*?)\n            \}',
      ).firstMatch(script);
      expect(fallback, isNotNull);
      expect(
        fallback!.group(1),
        contains('signingConfigs.getByName("release")'),
      );
      final missingKeystore = fallback.group(2)!;
      expect(missingKeystore, contains('logger.warn('));
      expect(missingKeystore, contains('android/key.properties is missing'));
      expect(missingKeystore, contains('will use the debug key'));
      expect(missingKeystore, contains('before distribution'));
      expect(missingKeystore, contains('signingConfigs.getByName("debug")'));
    },
  );
}
