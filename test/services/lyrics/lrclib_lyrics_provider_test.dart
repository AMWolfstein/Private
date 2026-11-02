import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sistrum/services/lyrics/lrclib_lyrics_provider.dart';
import 'package:sistrum/services/lyrics/online_lyrics_search.dart';

Uri? lastRequest;

LrcLibLyricsProvider _provider(http.Response response) => LrcLibLyricsProvider(
  client: MockClient((request) async {
    lastRequest = request.url;
    return response;
  }),
);

void main() {
  const query = OnlineLyricsQuery(
    title: 'Song',
    artist: 'Artist',
    album: 'Album',
    durationSeconds: 200,
  );

  setUp(() => lastRequest = null);

  test('sends title, artist, album and rounded duration', () async {
    await _provider(http.Response('{}', 200)).find(query);

    expect(lastRequest!.host, 'lrclib.net');
    expect(lastRequest!.queryParameters, {
      'track_name': 'Song',
      'artist_name': 'Artist',
      'album_name': 'Album',
      'duration': '200',
    });
  });

  test('returns line-synced text and classifies it', () async {
    final body = jsonEncode({
      'duration': 200,
      'syncedLyrics': '[00:01.00]Hi there',
      'plainLyrics': 'Hi there',
    });
    final candidate = await _provider(http.Response(body, 200)).find(query);

    expect(candidate!.provider, 'lrclib');
    expect(candidate.timing, LyricsTiming.lineSynced);
    expect(candidate.text, '[00:01.00]Hi there');
  });

  test('falls back to plain text when there is no synced text', () async {
    final body = jsonEncode({
      'duration': 200,
      'syncedLyrics': null,
      'plainLyrics': 'Hi there',
    });
    final candidate = await _provider(http.Response(body, 200)).find(query);

    expect(candidate!.timing, LyricsTiming.plain);
  });

  test('a duration far from the song is not a match', () async {
    final body = jsonEncode({
      'duration': 260,
      'syncedLyrics': '[00:01.00]Hi there',
    });
    expect(await _provider(http.Response(body, 200)).find(query), isNull);
  });

  test('404 means not found, not an error', () async {
    expect(await _provider(http.Response('', 404)).find(query), isNull);
  });

  test('other HTTP errors throw so the search can report them', () async {
    expect(
      _provider(http.Response('', 500)).find(query),
      throwsA(isA<http.ClientException>()),
    );
  });
}
