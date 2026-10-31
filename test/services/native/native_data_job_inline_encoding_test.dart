import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/native/native_data_jobs.dart';

void main() {
  group('NativeDataJobs.isInlineEncodable', () {
    test('small plain JSON data encodes inline', () {
      expect(
        NativeDataJobs.isInlineEncodable({
          'operation': 'parse_lyrics',
          'flags': [1, 2.5, true, null],
          'nested': {'title': 'Song'},
        }),
        isTrue,
      );
    });

    test('a request over the budget takes the isolate path', () {
      final big = 'x' * (64 * 1024 + 1);
      expect(NativeDataJobs.isInlineEncodable({'text': big}), isFalse);
    });

    test('many small nodes are bounded too', () {
      final many = List<int>.generate(70 * 1024, (i) => i);
      expect(NativeDataJobs.isInlineEncodable(many), isFalse);
    });

    test('values the encoder may reject keep the isolate path', () {
      expect(
        NativeDataJobs.isInlineEncodable({'when': DateTime(2026)}),
        isFalse,
      );
      expect(NativeDataJobs.isInlineEncodable({1: 'non-string key'}), isFalse);
    });
  });
}
