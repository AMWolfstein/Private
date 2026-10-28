import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/utils/artist_utils.dart';

void main() {
  test('featured variants and confirmed conjunction credits are clickable', () {
    expect(splitArtistNames('One featured Two'), ['One', 'Two']);
    expect(splitArtistNames('One feature Two'), ['One', 'Two']);
    expect(splitArtistNames('One and Two', creditedArtistCount: 2), [
      'One',
      'Two',
    ]);
    expect(splitArtistNames('Florence and the Machine'), [
      'Florence and the Machine',
    ]);
    expect(
      splitArtistNames('Florence and the Machine', creditedArtistCount: 1),
      ['Florence and the Machine'],
    );
  });
}
