import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/animated_artwork/apple_artwork_parse.dart';

String _jwt(Object payload) {
  String seg(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${seg({'alg': 'ES256', 'typ': 'JWT', 'kid': 'WebPlayKid'})}'
      '.${seg(payload)}.c2lnbmF0dXJl';
}

Map<String, dynamic> _video(String key, {String? preview}) => {
  key: {
    'video': 'https://video.example/$key/master.m3u8',
    if (preview != null) 'previewFrame': {'url': preview},
  },
};

AppleArtworkCandidate _album(
  String name,
  String artist, {
  String id = '1',
  int? trackCount,
  String? upc,
}) => AppleArtworkCandidate(
  kind: AppleArtworkKind.album,
  id: id,
  name: name,
  artistName: artist,
  trackCount: trackCount,
  upc: upc,
);

void main() {
  group('developer token', () {
    test('reads the devToken parameter from the browse page', () {
      expect(
        extractAppleDeveloperToken(
          '<iframe src="x?devToken=aaa.bbb.ccc&x=1"></iframe>',
        ),
        'aaa.bbb.ccc',
      );
    });

    test('finds a web-player JWT written directly in the page', () {
      final token = _jwt({'exp': 2000000000});
      expect(
        extractAppleDeveloperToken('var t="$token";'),
        token,
      );
    });

    test('returns null when no token-shaped string exists', () {
      expect(extractAppleDeveloperToken('<html>nothing here</html>'), isNull);
    });

    test('reads the expiry claim in milliseconds', () {
      expect(
        appleTokenExpiryMillis(_jwt({'exp': 1700000000})),
        1700000000 * 1000,
      );
    });

    test('rejects a token without a usable expiry', () {
      expect(appleTokenExpiryMillis(_jwt({'sub': 'x'})), isNull);
      expect(appleTokenExpiryMillis('not-a-jwt'), isNull);
    });
  });

  group('Apple Music links', () {
    test('reads album and artist links, ignoring the slug and tracks', () {
      final album = parseAppleArtworkUrl(
        'https://music.apple.com/us/album/abbey-road/1441164426?i=1441164427',
      );
      expect(album?.kind, AppleArtworkKind.album);
      expect(album?.id, '1441164426');

      final artist = parseAppleArtworkUrl(
        'https://music.apple.com/gb/artist/the-beatles/136975',
      );
      expect(artist?.kind, AppleArtworkKind.artist);
      expect(artist?.id, '136975');
    });

    test('rejects songs, playlists and other hosts', () {
      expect(
        parseAppleArtworkUrl('https://music.apple.com/us/song/x/123'),
        isNull,
      );
      expect(
        parseAppleArtworkUrl('https://example.com/us/album/x/123'),
        isNull,
      );
    });
  });

  group('motion video choice', () {
    test('album covers take only tall variants', () {
      final editorial = {
        ..._video('motionArtistWide16x9'),
        ..._video('motionDetailTall'),
      };
      final picked = pickAppleMotionVideo(editorial, tallOnly: true);
      expect(picked?.key, 'motionDetailTall');
      expect(picked?.tall, isTrue);
    });

    test('an album with only a wide video has no album motion', () {
      expect(
        pickAppleMotionVideo(
          _video('motionArtistWide16x9'),
          tallOnly: true,
        ),
        isNull,
      );
    });

    test('artists accept any variant in priority order', () {
      final picked = pickAppleMotionVideo(
        {
          ..._video('motionArtistWide16x9'),
          ..._video('motionArtistSquare1x1'),
        },
        tallOnly: false,
      );
      expect(picked?.key, 'motionArtistSquare1x1');
    });

    test('a non-https video URL is ignored', () {
      expect(
        pickAppleMotionVideo(
          {
            'motionDetailTall': {'video': 'http://insecure.example/a.m3u8'},
          },
          tallOnly: true,
        ),
        isNull,
      );
    });

    test('the preview frame fills the template at a fixed list size', () {
      final picked = pickAppleMotionVideo(
        _video(
          'motionDetailTall',
          preview: 'https://img.example/{w}x{h}.jpg',
        ),
        tallOnly: true,
      );
      expect(picked?.previewUrl, 'https://img.example/600x800.jpg');
    });
  });

  group('search results', () {
    test('parses albums and artists and keeps their static previews', () {
      final results = parseAppleSearchResults({
        'results': {
          'albums': {
            'data': [
              {
                'id': '10',
                'attributes': {
                  'name': 'Album',
                  'artistName': 'Artist',
                  'trackCount': 12,
                  'artwork': {'url': 'https://a.example/{w}x{h}.jpg'},
                },
              },
            ],
          },
          'artists': {
            'data': [
              {
                'id': '20',
                'attributes': {'name': 'Artist'},
              },
            ],
          },
        },
      });
      expect(results.map((r) => r.kind), [
        AppleArtworkKind.album,
        AppleArtworkKind.artist,
      ]);
      expect(results.first.trackCount, 12);
      expect(results.first.previewUrl, 'https://a.example/600x600.jpg');
    });

    test('a response without a results object is malformed', () {
      expect(
        () => parseAppleSearchResults({'data': <Object?>[]}),
        throwsA(isA<AppleArtworkUnavailable>()),
      );
    });

    test('a section whose data is not a list is malformed', () {
      expect(
        () => parseAppleSearchResults({
          'results': {'albums': {'data': 'oops'}},
        }),
        throwsA(isA<AppleArtworkUnavailable>()),
      );
    });

    test('entries with non-numeric or missing ids are skipped', () {
      final results = parseAppleSearchResults({
        'results': {
          'artists': {
            'data': [
              {'id': 'abc', 'attributes': {'name': 'X'}},
              {'attributes': {'name': 'Y'}},
              {'id': '5', 'attributes': {'name': 'Z'}},
            ],
          },
        },
      });
      expect(results.map((r) => r.id), ['5']);
    });
  });

  group('album matching', () {
    test('an identical title and album artist matches', () {
      final match = matchAppleAlbum(
        albumTitle: 'Abbey Road',
        albumArtist: 'The Beatles',
        candidates: [_album('Abbey Road', 'The Beatles')],
      );
      expect(match.outcome, AppleMatchOutcome.matched);
    });

    test('a deluxe edition never matches the standard release', () {
      final match = matchAppleAlbum(
        albumTitle: 'Abbey Road',
        albumArtist: 'The Beatles',
        candidates: [_album('Abbey Road (Deluxe Edition)', 'The Beatles')],
      );
      expect(match.outcome, AppleMatchOutcome.noMatch);
    });

    test('a different track count means a different edition', () {
      final match = matchAppleAlbum(
        albumTitle: 'Abbey Road',
        albumArtist: 'The Beatles',
        localTrackCount: 17,
        candidates: [_album('Abbey Road', 'The Beatles', trackCount: 17 + 4)],
      );
      expect(match.outcome, AppleMatchOutcome.noMatch);
    });

    test('a loose shared word never matches', () {
      final match = matchAppleAlbum(
        albumTitle: 'Love',
        albumArtist: 'Nina',
        candidates: [_album('Love Songs', 'Nina Simone')],
      );
      expect(match.outcome, AppleMatchOutcome.noMatch);
    });

    test('a collaboration written with another separator still matches', () {
      final match = matchAppleAlbum(
        albumTitle: 'Together',
        albumArtist: 'Artist A, Artist B',
        candidates: [_album('Together', 'Artist A & Artist B')],
      );
      expect(match.outcome, AppleMatchOutcome.matched);
    });

    test('a collaboration with a different member does not match', () {
      final match = matchAppleAlbum(
        albumTitle: 'Together',
        albumArtist: 'Artist A & Artist B',
        candidates: [_album('Together', 'Artist A & Artist C')],
      );
      expect(match.outcome, AppleMatchOutcome.noMatch);
    });

    test('an exact Arabic album and artist match', () {
      final match = matchAppleAlbum(
        albumTitle: 'أم كلثوم',
        albumArtist: 'أم كلثوم',
        candidates: [_album('أم كلثوم', 'أم كلثوم')],
      );
      expect(match.outcome, AppleMatchOutcome.matched);
    });

    test('two exact releases are ambiguous unless a UPC settles it', () {
      final candidates = [
        _album('Live', 'Band', id: '1', upc: '111'),
        _album('Live', 'Band', id: '2', upc: '222'),
      ];
      expect(
        matchAppleAlbum(
          albumTitle: 'Live',
          albumArtist: 'Band',
          candidates: candidates,
        ).outcome,
        AppleMatchOutcome.ambiguous,
      );
      final byUpc = matchAppleAlbum(
        albumTitle: 'Live',
        albumArtist: 'Band',
        localUpc: '222',
        candidates: candidates,
      );
      expect(byUpc.outcome, AppleMatchOutcome.matched);
      expect(byUpc.candidate?.id, '2');
    });

    test('an empty title or artist never matches', () {
      expect(
        matchAppleAlbum(
          albumTitle: '  ',
          albumArtist: 'Band',
          candidates: [_album('', 'Band')],
        ).outcome,
        AppleMatchOutcome.noMatch,
      );
    });
  });

  group('artist matching', () {
    test('only the exact normalized name matches', () {
      final match = matchAppleArtist(
        artistName: 'AC/DC',
        candidates: [
          const AppleArtworkCandidate(
            kind: AppleArtworkKind.artist,
            id: '9',
            name: 'AC DC',
          ),
        ],
      );
      expect(match.outcome, AppleMatchOutcome.matched);
    });

    test('a first name alone never matches a full name', () {
      final match = matchAppleArtist(
        artistName: 'Nina',
        candidates: [
          const AppleArtworkCandidate(
            kind: AppleArtworkKind.artist,
            id: '9',
            name: 'Nina Simone',
          ),
        ],
      );
      expect(match.outcome, AppleMatchOutcome.noMatch);
    });

    test('albums in the results are not artist matches', () {
      final match = matchAppleArtist(
        artistName: 'Abbey Road',
        candidates: [_album('Abbey Road', 'The Beatles')],
      );
      expect(match.outcome, AppleMatchOutcome.noMatch);
    });
  });
}
