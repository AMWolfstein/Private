import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sistrum/services/animated_artwork/apple_artwork_client.dart';
import 'package:sistrum/services/animated_artwork/apple_artwork_parse.dart';

String _jwt(int expSeconds) {
  String seg(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${seg({'alg': 'ES256', 'typ': 'JWT', 'kid': 'WebPlayKid'})}'
      '.${seg({'exp': expSeconds})}.c2ln';
}

const _search = {
  'results': {
    'albums': {
      'data': [
        {
          'id': '42',
          'attributes': {'name': 'Album', 'artistName': 'Artist'},
        },
      ],
    },
  },
};

/// Scripted Apple: counts page loads and catalog calls, and answers from
/// [catalog] (a function of the request path and token).
class _FakeApple {
  _FakeApple({
    required this.token,
    this.pageHtml,
    this.bundle,
    List<http.Response> catalog = const [],
  }) : _queue = List.of(catalog);

  String token;
  final String? pageHtml;
  final String? bundle;
  final List<http.Response> _queue;
  int pageLoads = 0;
  final tokensUsed = <String>[];
  final catalogCalls = <String>[];

  http.Client build() => MockClient((request) async {
    final url = request.url.toString();
    if (url == 'https://music.apple.com/us/browse') {
      pageLoads++;
      return http.Response(pageHtml ?? 'devToken=$token', 200);
    }
    if (bundle != null && url == 'https://music.apple.com/assets/index.js') {
      return http.Response(bundle!, 200);
    }
    if (url.startsWith('https://amp-api.music.apple.com/v1/catalog/us/')) {
      final auth = request.headers['Authorization'] ?? '';
      tokensUsed.add(auth.replaceFirst('Bearer ', ''));
      final path = url.substring(
        'https://amp-api.music.apple.com/v1/catalog/us/'.length,
      );
      catalogCalls.add(path);
      if (_queue.isNotEmpty) return _queue.removeAt(0);
      return http.Response(jsonEncode(_search), 200);
    }
    return http.Response('nope', 404);
  });
}

void main() {
  test('reads the token from the page and reuses it', () async {
    final apple = _FakeApple(token: 'aaa.bbb.ccc');
    final api = AppleArtworkClient(client: apple.build());

    final first = await api.search('abbey road');
    await api.search('the beatles');

    expect(first.single.id, '42');
    expect(apple.pageLoads, 1);
    expect(apple.tokensUsed, ['aaa.bbb.ccc', 'aaa.bbb.ccc']);
  });

  test('a browse page larger than 2 MiB still reaches its token', () async {
    // Apple's browse page is about 2.4 MiB and only lists its scripts; the
    // token sits in the script, so the page must not be refused for size.
    final apple = _FakeApple(
      token: 'big.pag.e',
      pageHtml:
          '${' ' * (3 * 1024 * 1024)}<script src="/assets/index.js"></script>',
      bundle: 'devToken=big.pag.e',
    );
    final api = AppleArtworkClient(client: apple.build());

    final results = await api.search('x');
    expect(results.single.id, '42');
    expect(apple.tokensUsed, ['big.pag.e']);
  });

  test('a browse page beyond the 8 MiB bound is still refused', () async {
    final apple = _FakeApple(
      token: 'a.b.c',
      pageHtml: ' ' * (9 * 1024 * 1024),
    );
    final api = AppleArtworkClient(client: apple.build());
    await expectLater(
      api.search('x'),
      throwsA(isA<AppleArtworkUnavailable>()),
    );
  });

  test('a token past its expiry is fetched again', () async {
    var now = DateTime.utc(2030, 1, 1);
    final apple = _FakeApple(token: _jwt(now.millisecondsSinceEpoch ~/ 1000 + 600));
    final api = AppleArtworkClient(client: apple.build(), clock: () => now);

    await api.search('x');
    expect(apple.pageLoads, 1);

    // Within the five-minute margin, so the token is no longer trusted.
    now = now.add(const Duration(minutes: 6));
    await api.search('x');
    expect(apple.pageLoads, 2);
  });

  test('a rejected token is refreshed once and the request retried', () async {
    final apple = _FakeApple(
      token: 'first.tok.en',
      catalog: [
        http.Response('unauthorized', 401),
        http.Response(jsonEncode(_search), 200),
      ],
    );
    final api = AppleArtworkClient(client: apple.build());

    final results = await api.search('x');
    expect(results.single.id, '42');
    expect(apple.pageLoads, 2);
  });

  test('a token that is rejected twice is unavailable, not no-match', () async {
    final apple = _FakeApple(
      token: 'a.b.c',
      catalog: [
        http.Response('no', 401),
        http.Response('no', 401),
      ],
    );
    final api = AppleArtworkClient(client: apple.build());
    await expectLater(
      api.search('x'),
      throwsA(isA<AppleArtworkUnavailable>()),
    );
  });

  test('transient errors are retried with bounded pauses', () async {
    final pauses = <Duration>[];
    final apple = _FakeApple(
      token: 'a.b.c',
      catalog: [
        http.Response('busy', 503, headers: {'retry-after': '2'}),
        http.Response('busy', 429),
        http.Response(jsonEncode(_search), 200),
      ],
    );
    final api = AppleArtworkClient(
      client: apple.build(),
      pause: (d) async => pauses.add(d),
    );

    final results = await api.search('x');
    expect(results, hasLength(1));
    expect(pauses.first, const Duration(seconds: 2));
    expect(pauses, hasLength(2));
  });

  test('retries stop after the attempt limit and report unavailable', () async {
    final apple = _FakeApple(
      token: 'a.b.c',
      catalog: List.generate(5, (_) => http.Response('down', 500)),
    );
    final api = AppleArtworkClient(
      client: apple.build(),
      attempts: 3,
      pause: (_) async {},
    );
    await expectLater(
      api.search('x'),
      throwsA(isA<AppleArtworkUnavailable>()),
    );
    expect(apple.catalogCalls, hasLength(3));
  });

  test('a client error other than 401 is not retried and is unavailable', () async {
    final apple = _FakeApple(
      token: 'a.b.c',
      catalog: [http.Response('bad', 400)],
    );
    final api = AppleArtworkClient(client: apple.build(), pause: (_) async {});
    await expectLater(
      api.search('x'),
      throwsA(isA<AppleArtworkUnavailable>()),
    );
    expect(apple.catalogCalls, hasLength(1));
  });

  test('a malformed JSON body is unavailable, never an empty result', () async {
    final apple = _FakeApple(
      token: 'a.b.c',
      catalog: [http.Response('<html>', 200)],
    );
    final api = AppleArtworkClient(client: apple.build());
    await expectLater(
      api.search('x'),
      throwsA(isA<AppleArtworkUnavailable>()),
    );
  });

  test('a page without a token is unavailable', () async {
    final apple = _FakeApple(
      token: '',
      pageHtml: '<html>no token here</html>',
    );
    final api = AppleArtworkClient(client: apple.build());
    await expectLater(
      api.search('x'),
      throwsA(isA<AppleArtworkUnavailable>()),
    );
  });

  test('a token inside a page script is found when the page has none', () async {
    final token = _jwt(2000000000);
    final apple = _FakeApple(
      token: token,
      pageHtml: '<script src="/assets/index.js"></script>',
      bundle: 'var t="$token";',
    );
    final api = AppleArtworkClient(client: apple.build());
    final results = await api.search('x');
    expect(results, hasLength(1));
    expect(apple.tokensUsed.single, token);
  });

  test('album video lookup returns the tall motion video', () async {
    final apple = _FakeApple(
      token: 'a.b.c',
      catalog: [
        http.Response(
          jsonEncode({
            'data': [
              {
                'id': '42',
                'attributes': {
                  'editorialVideo': {
                    'motionDetailTall': {
                      'video': 'https://video.example/t.m3u8',
                    },
                    'motionArtistWide16x9': {
                      'video': 'https://video.example/w.m3u8',
                    },
                  },
                },
              },
            ],
          }),
          200,
        ),
      ],
    );
    final api = AppleArtworkClient(client: apple.build());
    final video = await api.albumVideo('42');
    expect(video?.url, 'https://video.example/t.m3u8');
    expect(apple.catalogCalls.single, startsWith('albums/42?extend='));
  });

  test('a wrongly shaped editorialVideo is unavailable', () async {
    final apple = _FakeApple(
      token: 'a.b.c',
      catalog: [
        http.Response(
          jsonEncode({
            'data': [
              {
                'id': '1',
                'attributes': {'editorialVideo': 'oops'},
              },
            ],
          }),
          200,
        ),
      ],
    );
    final api = AppleArtworkClient(client: apple.build());
    await expectLater(
      api.artistVideo('1'),
      throwsA(isA<AppleArtworkUnavailable>()),
    );
  });

  test('an empty data list means the entity has no video', () async {
    final apple = _FakeApple(
      token: 'a.b.c',
      catalog: [http.Response('{"data":[]}', 200)],
    );
    final api = AppleArtworkClient(client: apple.build());
    expect(await api.artistVideo('1'), isNull);
  });
}
