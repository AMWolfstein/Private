import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/utils/playback/progress_stream_poller.dart';

ProgressStreamPoller<int> _poller({
  Stream<int> Function()? stream,
  Future<int> Function()? poll,
  Future<void> Function(int progress)? onProgress,
  Duration pollingInterval = const Duration(milliseconds: 5),
  Duration bootstrapTimeout = const Duration(milliseconds: 500),
  void Function(Object error)? onStreamProcessingError,
  void Function(Object error)? onStreamFailed,
  void Function()? onStreamTimeout,
  void Function(Object error)? onPollError,
  bool Function()? shouldPollTick,
}) => ProgressStreamPoller<int>(
  streamProvider: stream ?? () => const Stream<int>.empty(),
  pollProvider: poll ?? () async => 1,
  onProgress: onProgress ?? (_) async {},
  pollingInterval: pollingInterval,
  bootstrapTimeout: bootstrapTimeout,
  onStreamProcessingError: onStreamProcessingError ?? (_) {},
  onStreamFailed: onStreamFailed ?? (_) {},
  onStreamTimeout: onStreamTimeout ?? () {},
  onPollError: onPollError ?? (_) {},
  shouldPollTick: shouldPollTick,
);

Future<void> _wait(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

void main() {
  test('pollOnce forwards the fetched value to onProgress', () async {
    final received = <int>[];
    final poller = _poller(
      poll: () async => 42,
      onProgress: (progress) async => received.add(progress),
    );
    await poller.pollOnce((_) {});
    expect(received, [42]);
    poller.stop();
  });

  test('error logging stops after the threshold until a success', () async {
    final logged = <Object>[];
    var fail = true;
    final poller = _poller(
      poll: () async {
        if (fail) throw StateError('failure');
        return 1;
      },
    );

    for (var i = 0; i < 5; i++) {
      await poller.pollOnce(logged.add);
    }
    expect(logged, hasLength(3), reason: 'errors past 3 are throttled');

    fail = false;
    await poller.pollOnce(logged.add);
    fail = true;
    for (var i = 0; i < 4; i++) {
      await poller.pollOnce(logged.add);
    }
    expect(logged, hasLength(6), reason: 'a success resets the counter');
    poller.stop();
  });

  test('the in-flight guard drops overlapping fetches', () async {
    final gate = Completer<int>();
    var fetches = 0;
    final poller = _poller(
      poll: () {
        fetches++;
        return gate.future;
      },
    );
    final first = poller.pollOnce((_) {});
    await poller.pollOnce((_) {});
    expect(fetches, 1);
    gate.complete(1);
    await first;
    poller.stop();
  });

  test('polling runs on the timer and stops after stop()', () async {
    var fetches = 0;
    final poller = _poller(
      poll: () async {
        fetches++;
        return 1;
      },
    );
    poller.start(useStream: false);
    await _wait(40);
    expect(fetches, greaterThan(0));

    poller.stop();
    final afterStop = fetches;
    await _wait(40);
    expect(fetches, afterStop);
  });

  test('the shouldPollTick gate skips ticks without fetching', () async {
    var fetches = 0;
    final poller = _poller(
      poll: () async {
        fetches++;
        return 1;
      },
      shouldPollTick: () => false,
    );
    poller.start(useStream: false);
    await _wait(30);
    poller.stop();
    expect(fetches, 0);
  });

  test('a stream that never emits falls back to polling on timeout', () async {
    var timeouts = 0;
    var fetches = 0;
    final poller = _poller(
      stream: () => StreamController<int>().stream,
      poll: () async {
        fetches++;
        return 1;
      },
      bootstrapTimeout: const Duration(milliseconds: 10),
      onStreamTimeout: () => timeouts++,
    );
    poller.start(useStream: true);
    await _wait(60);
    poller.stop();
    expect(timeouts, 1);
    expect(fetches, greaterThan(0));
  });

  test('a stream error after events reports failure and polls', () async {
    final controller = StreamController<int>();
    addTearDown(controller.close);
    final failures = <Object>[];
    var fetches = 0;
    final poller = _poller(
      stream: () => controller.stream,
      poll: () async {
        fetches++;
        return 1;
      },
      bootstrapTimeout: const Duration(seconds: 5),
      onStreamFailed: failures.add,
    );
    poller.start(useStream: true);
    controller.add(7);
    await _wait(5);
    controller.addError(StateError('stream dropped'));
    await _wait(40);
    poller.stop();

    expect(failures, hasLength(1));
    expect(fetches, greaterThan(0));
  });

  test('stream events are delivered and not polled', () async {
    final controller = StreamController<int>();
    addTearDown(controller.close);
    final received = <int>[];
    var fetches = 0;
    final poller = _poller(
      stream: () => controller.stream,
      poll: () async {
        fetches++;
        return 0;
      },
      onProgress: (progress) async => received.add(progress),
      bootstrapTimeout: const Duration(seconds: 5),
    );
    poller.start(useStream: true);
    controller.add(10);
    await _wait(5);
    controller.add(20);
    await _wait(5);
    poller.stop();
    expect(received, [10, 20]);
    expect(fetches, 0);
  });
}
