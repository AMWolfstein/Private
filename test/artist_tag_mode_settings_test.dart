import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/models/settings.dart';

void main() {
  test('retired artist mode and output settings are ignored on import', () {
    final settings = AppSettings.fromJson({
      'artistTagMode': 'primary',
      'lastSeenVersion': 'old',
      'downloadDirectory': '/foreign',
      'downloadDirectoryBookmark': 'bookmark',
      'storageMode': 'saf',
      'downloadTreeUri': 'content://foreign',
    });
    for (final key in [
      'artistTagMode',
      'lastSeenVersion',
      'downloadDirectory',
      'downloadDirectoryBookmark',
      'storageMode',
      'downloadTreeUri',
    ]) {
      expect(settings.toJson().containsKey(key), isFalse);
    }
  });
}
