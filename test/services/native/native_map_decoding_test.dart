import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/native/native_channel.dart';

void main() {
  group('nativeDecodeMapResult', () {
    test('accepts a JSON object string and a Map', () {
      expect(nativeDecodeMapResult('{"progress_pct": 12}', 'op'), {
        'progress_pct': 12,
      });
      expect(nativeDecodeMapResult(<Object?, Object?>{'a': 1}, 'op'), {'a': 1});
    });

    test('rejects null, an empty string and any other shape', () {
      for (final bad in <Object?>[null, '', '[]', '"text"', 42, '{']) {
        expect(
          () => nativeDecodeMapResult(bad, 'getLibraryScanProgress'),
          throwsA(isA<FormatException>()),
          reason: 'payload $bad',
        );
      }
    });

    test('names the method in the error so a contract break is traceable', () {
      expect(
        () => nativeDecodeMapResult(null, 'getLibraryScanProgress'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('getLibraryScanProgress'),
          ),
        ),
      );
    });
  });
}
