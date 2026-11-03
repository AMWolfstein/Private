import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/artist_images/artist_image_auto_pass.dart';

void main() {
  test('orders artist names like the Artists list, case-insensitively', () {
    expect(
      sortArtistNamesLikeArtistsList(['Zed', 'Adele', 'abc', 'ادل', 'Beta']),
      ['abc', 'Adele', 'Beta', 'Zed', 'ادل'],
    );
  });

  test('keeps the raw name as the tie-break for equal keys', () {
    expect(sortArtistNamesLikeArtistsList(['adele', 'Adele']), [
      'Adele',
      'adele',
    ]);
  });
}
