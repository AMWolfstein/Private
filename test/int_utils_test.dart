import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/utils/int_utils.dart';

void main() {
  test('readPositiveInt accepts positive numbers and truncates them', () {
    expect(readPositiveInt(24), 24);
    expect(readPositiveInt(44100.0), 44100);
    expect(readPositiveInt(24.9), 24);
  });

  test('readPositiveInt rejects null, zero and negative values', () {
    expect(readPositiveInt(null), isNull);
    expect(readPositiveInt(0), isNull);
    expect(readPositiveInt(-1), isNull);
    expect(readPositiveInt(0.5), isNull);
  });

  test('readPositiveInt parses positive integer strings only', () {
    expect(readPositiveInt('96000'), 96000);
    expect(readPositiveInt('0'), isNull);
    expect(readPositiveInt('-3'), isNull);
    expect(readPositiveInt('abc'), isNull);
    expect(readPositiveInt(''), isNull);
  });
}
