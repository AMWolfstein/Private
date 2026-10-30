import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/utils/lyrics_parser.dart';

const _ttmlNamespace = 'xmlns="http://www.w3.org/ns/ttml"';

String _tt(String body) =>
    '<tt $_ttmlNamespace xmlns:ttm="http://www.w3.org/ns/ttml#metadata">'
    '<body><div>$body</div></body></tt>';

void main() {
  test('timed TTML paragraphs become synced lines with their end times', () {
    final parsed = LyricsParser.parse(
      _tt(
        '<p begin="00:01.000" end="00:03.000">Hello world</p>'
        '<p begin="00:03.500" end="00:06.000">Second line</p>',
      ),
    );
    expect(parsed.synced, isTrue);
    expect(parsed.wordSynced, isFalse);
    expect(parsed.lines.map((line) => line.text), [
      'Hello world',
      'Second line',
    ]);
    expect(parsed.lines.first.time, const Duration(seconds: 1));
    expect(parsed.lines.first.end, const Duration(seconds: 3));
    expect(parsed.plainText, 'Hello world\nSecond line');
  });

  test('word spans with their own timing make the lyrics word-synced', () {
    final parsed = LyricsParser.parse(
      _tt(
        '<p begin="00:01.000" end="00:02.000">'
        '<span begin="00:01.000" end="00:01.400">Hel</span>'
        '<span begin="00:01.400" end="00:02.000">lo</span>'
        '</p>',
      ),
    );
    expect(parsed.synced, isTrue);
    expect(parsed.wordSynced, isTrue);
    expect(parsed.lines.single.text, 'Hello');
    expect(parsed.lines.single.words, hasLength(2));
  });

  test('untimed TTML keeps its text and is not shown as unsynced markup', () {
    final parsed = LyricsParser.parse(
      _tt('<p>First untimed line</p><p>Second untimed line</p>'),
    );
    expect(parsed.synced, isFalse);
    expect(parsed.lines, isEmpty);
    expect(parsed.plainText, 'First untimed line\nSecond untimed line');
    expect(parsed.plainText, isNot(contains('<')));
  });

  test('a background vocal line is marked as background', () {
    final parsed = LyricsParser.parse(
      _tt(
        '<p begin="00:01.000" end="00:04.000">'
        'Lead'
        '<span ttm:role="x-bg" begin="00:02.000" end="00:03.000">(echo)</span>'
        '</p>',
      ),
    );
    final background = parsed.lines.where((line) => line.isBackground);
    expect(background.map((line) => line.text), ['(echo)']);
  });

  test('a plain LRC file is still read as timed lyrics', () {
    final parsed = LyricsParser.parse('[00:01.00]Hi there\n[00:04.00]Bye');
    expect(parsed.synced, isTrue);
    expect(parsed.lines.map((line) => line.text), ['Hi there', 'Bye']);
  });
}
