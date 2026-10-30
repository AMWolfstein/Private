import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/utils/scan/local_library_scan_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final value in [
    null,
    'bad date',
    false,
    <String>['wrong type'],
    9223372036854775807,
  ]) {
    test('invalid last scan value $value is ignored', () async {
      SharedPreferences.setMockInitialValues({
        localLibraryLastScannedAtKey: ?value,
      });
      expect(
        readLocalLibraryLastScannedAt(await SharedPreferences.getInstance()),
        isNull,
      );
    });
  }
  test('legacy integer and current ISO last scan values both load', () async {
    final date = DateTime.utc(2026, 10, 25);
    for (final value in [date.millisecondsSinceEpoch, date.toIso8601String()]) {
      SharedPreferences.setMockInitialValues({
        localLibraryLastScannedAtKey: value,
      });
      expect(
        readLocalLibraryLastScannedAt(
          await SharedPreferences.getInstance(),
        )?.toUtc(),
        date,
      );
    }
  });
}
