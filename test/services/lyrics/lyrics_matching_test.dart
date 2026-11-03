import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/lyrics/lyrics_matching.dart';

void main() {
  test('titles ignore case, brackets and punctuation', () {
    expect(
      normalizeTitle('Hey Jude (Remastered 2015)'),
      normalizeTitle('hey  jude!'),
    );
    expect(normalizeTitle('Song [Live]'), 'song');
  });

  test('a featured artist still matches the primary artist', () {
    expect(artistsMatch('Artist', 'Artist feat. Guest'), isTrue);
    expect(artistsMatch('Guest', 'Artist feat. Guest'), isTrue);
    expect(artistsMatch('Artist', 'Other'), isFalse);
    expect(artistsMatch('', 'Other'), isFalse);
  });

  test(
    'durations within three seconds match, unknown durations do not block',
    () {
      expect(durationsMatch(200, 202.5), isTrue);
      expect(durationsMatch(200, 204), isFalse);
      expect(durationsMatch(null, 204), isTrue);
      expect(durationsMatch(200, null), isTrue);
    },
  );

  test('parses clock durations', () {
    expect(parseClockSeconds('3:20'), 200);
    expect(parseClockSeconds('1:02:03'), 3723);
    expect(parseClockSeconds('45'), 45);
    expect(parseClockSeconds('x:y'), isNull);
    expect(parseClockSeconds(''), isNull);
  });

  test('a song matches only when title, artist and duration agree', () {
    expect(
      songMatches(
        wantedTitle: 'Yesterday',
        wantedArtist: 'The Beatles',
        wantedDuration: 125,
        foundTitle: 'Yesterday - Remastered',
        foundArtist: 'The Beatles',
        foundDuration: 126,
      ),
      isTrue,
    );
    expect(
      songMatches(
        wantedTitle: 'Yesterday',
        wantedArtist: 'The Beatles',
        wantedDuration: 125,
        foundTitle: 'Yesterday',
        foundArtist: 'The Beatles',
        foundDuration: 160,
      ),
      isFalse,
    );
  });
  test('shared first names never identify the same artist', () {
    expect(artistsMatch('محمد رمضان', 'محمد حماقي'), isFalse);
    expect(artistsMatch('John Lennon', 'John Legend'), isFalse);
    expect(
      artistsMatch('John Lennon', 'John Lennon feat. Paul McCartney'),
      isTrue,
    );
    expect(
      artistsMatch('Paul McCartney', 'John Lennon feat. Paul McCartney'),
      isTrue,
    );
    expect(artistsMatch('AC/DC', 'ac dc'), isTrue);
  });
}
