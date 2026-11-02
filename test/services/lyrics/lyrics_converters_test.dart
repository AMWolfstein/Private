import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/lyrics/lyrics_converters.dart';
import 'package:sistrum/services/lyrics/online_lyrics_search.dart';

void main() {
  group('timestamps', () {
    test('uses two fraction digits only when the millisecond value allows', () {
      expect(inlineTimestamp(1230), '00:01.23');
      expect(inlineTimestamp(1200), '00:01.20');
      expect(inlineTimestamp(1234), '00:01.234');
      expect(inlineTimestamp(61000), '01:01.00');
      expect(inlineTimestamp(-5), '00:00.00');
    });
  });

  group('proxy payloads', () {
    test('formats syllable lines with word start and end tags', () {
      final text = formatPaxLines('syllable', [
        {
          'timestamp': 1000,
          'text': [
            {'text': 'Hi', 'timestamp': 1000, 'endtime': 1300},
            {
              'text': 'there',
              'part': false,
              'timestamp': 1400,
              'endtime': 1900,
            },
          ],
        },
      ]);
      expect(
        text,
        '[00:01.00]<00:01.00>Hi <00:01.30><00:01.40>there <00:01.90>',
      );
      expect(LyricsTiming.detect(text), LyricsTiming.wordSynced);
    });

    test('joins parts without a space and repeats a start only once', () {
      final text = formatPaxLines('syllable', [
        {
          'timestamp': 0,
          'text': [
            {'text': 'Hel', 'part': true, 'timestamp': 0},
            {'text': 'lo', 'timestamp': 0},
          ],
        },
      ]);
      expect(text, '[00:00.00]<00:00.00>Hello');
    });

    test('line-timed content keeps the first text of each line', () {
      final text = formatPaxLines('line', [
        {
          'timestamp': 2000,
          'text': [
            {'text': 'Line one'},
          ],
        },
      ]);
      expect(text, '[00:02.00]Line one');
      expect(LyricsTiming.detect(text), LyricsTiming.lineSynced);
    });

    test('a JSON string body is the lyrics', () {
      expect(parseProxyPayload('"[00:01.00]Hi"'), '[00:01.00]Hi');
    });

    test('a plain text body is the lyrics', () {
      expect(parseProxyPayload('Hi there'), 'Hi there');
    });

    test('reads lyrics, then content, then plain lyrics in that order', () {
      expect(
        parseProxyPayload(jsonEncode({'lyrics_text': '[00:01.00]A'})),
        '[00:01.00]A',
      );
      expect(
        parseProxyPayload(
          jsonEncode({
            'content': [
              {
                'timestamp': 500,
                'text': [
                  {'text': 'B'},
                ],
              },
            ],
            'type': 'Line',
          }),
        ),
        '[00:00.50]B',
      );
      expect(parseProxyPayload(jsonEncode({'plain_lyrics': 'C'})), 'C');
    });

    test('an object without usable lyrics is a format failure', () {
      expect(
        () => parseProxyPayload('{"code":404}'),
        throwsA(isA<LyricsFormatException>()),
      );
      expect(
        () => parseProxyPayload(''),
        throwsA(isA<LyricsFormatException>()),
      );
    });
  });

  group('LyricsPlus (KPOE)', () {
    test('word kinds keep syllable timing and drop background syllables', () {
      final text = formatKpoe({
        'type': 'Word',
        'lyrics': [
          {
            'time': 1000,
            'text': '',
            'syllabus': [
              {'text': 'Hi ', 'time': 1000, 'isbackground': false},
              {'text': 'oh', 'time': 1500, 'isbackground': true},
              {'text': 'there', 'time': 1800, 'isbackground': false},
            ],
          },
        ],
      });
      expect(text, '[00:01.00]<00:01.00>Hi <00:01.80>there');
      expect(LyricsTiming.detect(text), LyricsTiming.wordSynced);
    });

    test('a line-only kind keeps each line text', () {
      final text = formatKpoe({
        'type': 'Line',
        'lyrics': [
          {'time': 3000, 'text': 'Only a line'},
        ],
      });
      expect(text, '[00:03.00]Only a line');
      expect(LyricsTiming.detect(text), LyricsTiming.lineSynced);
    });

    test('no lines is a format failure', () {
      expect(
        () => formatKpoe({'type': 'Word', 'lyrics': <Map<String, dynamic>>[]}),
        throwsA(isA<LyricsFormatException>()),
      );
    });
  });

  group('TTML', () {
    const document = '''
<tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata">
<body><div>
<p begin="00:00:01.000" end="00:00:03.000">
  <span begin="00:00:01.000" end="00:00:01.500">Hi</span>
  <span begin="00:00:01.500" end="00:00:02.000">there</span>
  <span ttm:role="x-bg" begin="00:00:02.000" end="00:00:03.000">(ooh)</span>
</p>
<p begin="00:00:04.000" end="00:00:05.000">Plain line &amp; more</p>
</div></body></tt>''';

    test('words come from spans and background spans are dropped', () {
      final text = formatTtml(document);
      expect(text.split('\n').first, startsWith('[00:01.00]<00:01.00>Hi'));
      expect(text, isNot(contains('ooh')));
      expect(LyricsTiming.detect(text), LyricsTiming.wordSynced);
    });

    test('a line without spans is line text with entities decoded', () {
      final text = formatTtml(document);
      expect(text.split('\n').last, '[00:04.00]Plain line & more');
    });

    test('invalid XML is a format failure', () {
      expect(() => formatTtml('<tt><p'), throwsA(isA<LyricsFormatException>()));
    });
  });

  group('Genius page', () {
    test('reads the lyric containers and skips excluded annotations', () {
      const html = '''
<html><body>
<div data-lyrics-container="true" class="x">
  Line one<br/>Line <a href="#" data-exclude-from-selection="true"><span>note</span></a>two<br>
  <img src="x.png">Line three
</div>
<div class="other">Not lyrics</div>
<div data-lyrics-container="true">Second&amp;block</div>
</body></html>''';
      final text = extractGeniusLyrics(html);
      expect(text, contains('Line one'));
      expect(text, contains('Line two'));
      expect(text, contains('Line three'));
      expect(text, isNot(contains('note')));
      expect(text, isNot(contains('Not lyrics')));
      expect(text, contains('Second&block'));
    });

    test('no container is a format failure', () {
      expect(
        () => extractGeniusLyrics('<html></html>'),
        throwsA(isA<LyricsFormatException>()),
      );
    });
  });

  test('QQ and Kugou bodies decode from base64 LRC', () {
    final encoded = base64.encode(utf8.encode('[00:01.00]Hi'));
    expect(decodeBase64Lyrics(encoded), '[00:01.00]Hi');
    expect(decodeBase64Lyrics('[00:01.00]Plain'), '[00:01.00]Plain');
  });
}
