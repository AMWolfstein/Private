import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sistrum/services/artist_images/deezer_artist_search.dart';

const _placeholder =
    'https://e-cdns-images.dzcdn.net/images/artist//1000x1000-000000-80-0-0.jpg';
const _portrait =
    'https://e-cdns-images.dzcdn.net/images/artist/abc123/1000x1000-000000-80-0-0.jpg';

DeezerArtistSearch _search(http.Response Function(http.Request) answer) =>
    DeezerArtistSearch(MockClient((request) async => answer(request)));

void main() {
  test('parses artists with portraits and their counts', () async {
    final search = _search((request) {
      expect(request.url.host, 'api.deezer.com');
      expect(request.url.queryParameters['q'], 'Sample Artist');
      return http.Response(
        jsonEncode({
          'data': [
            {
              'id': 42,
              'name': 'Sample Artist',
              'picture_xl': _portrait,
              'nb_fan': 1200,
              'nb_album': 7,
            },
          ],
        }),
        200,
      );
    });

    final artists = await search.search('Sample Artist');
    expect(artists, hasLength(1));
    expect(artists.single.name, 'Sample Artist');
    expect(artists.single.pictureUrl, _portrait);
    expect(artists.single.fans, 1200);
    expect(artists.single.albums, 7);
  });

  test('a placeholder picture is reported as no picture', () async {
    final artists = await _search(
      (_) => http.Response(
        jsonEncode({
          'data': [
            {'id': 1, 'name': 'Nobody', 'picture_xl': _placeholder},
          ],
        }),
        200,
      ),
    ).search('Nobody');
    expect(artists.single.pictureUrl, isNull);
  });

  test('no artists is an empty list, not an error', () async {
    final artists = await _search(
      (_) => http.Response(jsonEncode({'data': <Object>[]}), 200),
    ).search('Unknown');
    expect(artists, isEmpty);
  });

  test('an API error object is an outage, not an empty result', () async {
    final search = _search(
      (_) => http.Response(
        jsonEncode({
          'error': {'type': 'QuotaException', 'code': 4},
        }),
        200,
      ),
    );
    await expectLater(
      search.search('Sample'),
      throwsA(isA<DeezerUnavailable>()),
    );
  });

  test('an HTTP failure is an outage', () async {
    final search = _search((_) => http.Response('busy', 503));
    await expectLater(
      search.search('Sample'),
      throwsA(isA<DeezerUnavailable>()),
    );
  });

  test('a blank name is never sent', () async {
    var sent = false;
    final artists = await _search((_) {
      sent = true;
      return http.Response('{}', 200);
    }).search('   ');
    expect(artists, isEmpty);
    expect(sent, isFalse);
  });

  test('automatic matching ignores case, punctuation and spacing only', () {
    expect(isExactArtistMatch('AC/DC', 'ac dc'), isTrue);
    expect(isExactArtistMatch('  Sample   Artist ', 'sample artist'), isTrue);
    expect(isExactArtistMatch('Sample', 'Sample Artist'), isFalse);
    expect(isExactArtistMatch('Sample Artist', 'Sample Artists'), isFalse);
    expect(isExactArtistMatch('', ''), isFalse);
  });
}
