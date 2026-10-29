import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/screens/equalizer_screen.dart';

void main() {
  test('preset UTF-8 survives chunk boundaries and exact byte cap', () async {
    final bytes = utf8.encode('أغنية');
    expect(
      await readEqualizerPreset(
        Stream.fromIterable([bytes.sublist(0, 1), bytes.sublist(1)]),
      ),
      'أغنية',
    );
    expect(
      (await readEqualizerPreset(Stream.value(List.filled(65536, 32)))).length,
      65536,
    );
  });
  test('known oversized input is rejected without subscribing', () async {
    var subscribed = false;
    Stream<List<int>> source() async* {
      subscribed = true;
      yield [1];
    }

    await expectLater(
      readEqualizerPreset(source(), declaredSize: 65537),
      throwsFormatException,
    );
    expect(subscribed, isFalse);
  });
  test('unknown oversized stream cancels before reading its tail', () async {
    var tail = false;
    var closed = false;
    Stream<List<int>> source() async* {
      try {
        yield List.filled(65536, 32);
        yield [32];
        tail = true;
        yield [32];
      } finally {
        closed = true;
      }
    }

    await expectLater(readEqualizerPreset(source()), throwsFormatException);
    expect(tail, isFalse);
    expect(closed, isTrue);
  });
}
