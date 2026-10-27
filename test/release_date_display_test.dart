import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/utils/release_date_display.dart';

void main() {
  setUpAll(() => initializeDateFormatting('en'));
  test('release tags retain precision and reject overflow dates', () {
    for (final tag in ['20240305', '2024/3/5', '2024-03-05T00:00:00Z']) {
      expect(formatReleaseTag(tag, 'en'), 'Mar 5, 2024');
    }
    expect(formatReleaseTag('2024', 'en'), '2024');
    expect(formatReleaseTag('202403', 'en'), 'March 2024');
    for (final tag in [null, '', '2024-02-30', '20241305', '0000', 'no tag']) {
      expect(formatReleaseTag(tag, 'en'), isNull);
    }
  });
}
