import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/models/track.dart';
import 'package:sistrum/screens/library/collection_track_tile.dart';

Track _track({String? coverUrl}) => Track(
  id: 't',
  name: 'Song',
  artistName: 'Artist',
  albumName: 'Album',
  duration: 180,
  coverUrl: coverUrl,
);

void main() {
  test('a remote cover URL is used as the cover', () {
    expect(
      resolveRawCoverUrl(_track(coverUrl: 'https://example.com/cover.jpg')),
      'https://example.com/cover.jpg',
    );
  });

  test('surrounding spaces are trimmed from the cover URL', () {
    expect(
      resolveRawCoverUrl(_track(coverUrl: '  /covers/a.jpg  ')),
      '/covers/a.jpg',
    );
  });

  test('a content URI is never used directly as the cover', () {
    expect(
      resolveRawCoverUrl(_track(coverUrl: 'content://media/cover')),
      isNull,
    );
  });

  test('a blank or missing cover falls back to the local lookup', () {
    expect(resolveRawCoverUrl(_track(coverUrl: '   ')), isNull);
    expect(resolveRawCoverUrl(_track()), isNull);
  });
}
