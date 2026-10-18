import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/utils/artist_utils.dart';

void main() {
  test('primary artist mode survives settings round trips', () {
    final settings = const AppSettings().copyWith(
      artistTagMode: artistTagModePrimary,
    );
    expect(
      AppSettings.fromJson(settings.toJson()).artistTagMode,
      artistTagModePrimary,
    );
  });
}
