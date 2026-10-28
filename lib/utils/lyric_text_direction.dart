import 'package:flutter/widgets.dart' show TextDirection;

/// Direction of one lyric line from its first strong character, so Arabic,
/// Persian and Hebrew lines run right to left in a left-to-right app (and the
/// reverse). Lines without letters keep [fallback].
TextDirection lyricLineDirection(String text, TextDirection fallback) {
  for (final rune in text.runes) {
    // Digits, marks and punctuation are weak, even inside the Arabic block.
    if (!_isLetter(rune)) continue;
    return _isRightToLeft(rune) ? TextDirection.rtl : TextDirection.ltr;
  }
  return fallback;
}

bool _isRightToLeft(int rune) =>
    (rune >= 0x0590 && rune <= 0x08FF) ||
    (rune >= 0xFB1D && rune <= 0xFDFF) ||
    (rune >= 0xFE70 && rune <= 0xFEFF) ||
    (rune >= 0x10800 && rune <= 0x10FFF) ||
    (rune >= 0x1E800 && rune <= 0x1EFFF);

final _letter = RegExp(r'\p{L}', unicode: true);

bool _isLetter(int rune) {
  if (rune < 0x80) {
    return (rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A);
  }
  return _letter.hasMatch(String.fromCharCode(rune));
}
