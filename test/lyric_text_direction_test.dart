import 'package:flutter/widgets.dart' show TextDirection;
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/player/player_lyrics.dart';

void main() {
  test('Arabic, Persian and Hebrew lines run right to left', () {
    for (final text in ['مرحبا بالعالم', 'سلام دنیا', 'שלום עולם']) {
      expect(lyricLineDirection(text, TextDirection.ltr), TextDirection.rtl);
    }
  });

  test('Latin and other left-to-right scripts run left to right', () {
    for (final text in ['Hello world', 'こんにちは', 'Привет мир', 'café']) {
      expect(lyricLineDirection(text, TextDirection.rtl), TextDirection.ltr);
    }
  });

  test(
    'leading digits, punctuation and spaces do not decide the direction',
    () {
      expect(
        lyricLineDirection('  (12) ... مرحبا', TextDirection.ltr),
        TextDirection.rtl,
      );
      expect(
        lyricLineDirection('٣٤ - Hello', TextDirection.rtl),
        TextDirection.ltr,
      );
    },
  );

  test('lines without letters keep the fallback direction', () {
    expect(
      lyricLineDirection('♪ ... 123', TextDirection.rtl),
      TextDirection.rtl,
    );
    expect(lyricLineDirection('', TextDirection.ltr), TextDirection.ltr);
  });
}
