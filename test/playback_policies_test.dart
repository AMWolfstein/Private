import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/playback/core/playback_policies.dart';

void main() {
  group('PlayHistory', () {
    test('keeps only the newest entries', () {
      final history = PlayHistory(capacity: 3);
      for (var i = 0; i < 5; i++) {
        history.record(i);
      }
      expect(history.entries.toList(), [2, 3, 4]);
    });

    test('makeRoomAt shifts entries at or after the insert point', () {
      final history = PlayHistory()
        ..record(0)
        ..record(2)
        ..record(5);
      history.makeRoomAt(2);
      expect(history.entries.toList(), [0, 3, 6]);
    });

    test('dropQueueEntry forgets the removed entry and shifts later ones', () {
      final history = PlayHistory()
        ..record(0)
        ..record(2)
        ..record(3)
        ..record(1);
      history.dropQueueEntry(2);
      expect(history.entries.toList(), [0, 2, 1]);
    });

    test('removeLast and last follow the recorded order', () {
      final history = PlayHistory()
        ..record(4)
        ..record(7);
      expect(history.last, 7);
      history.removeLast();
      expect(history.last, 4);
      expect(history.length, 1);
    });
  });

  group('SleepTimer', () {
    test('fires once after its duration and clears its end time', () async {
      final timer = SleepTimer();
      var fired = 0;
      timer.start(const Duration(milliseconds: 5), () => fired++);
      expect(timer.endsAt, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(fired, 1);
      expect(timer.endsAt, isNull);
    });

    test('cancel prevents the callback', () async {
      final timer = SleepTimer();
      var fired = 0;
      timer.start(const Duration(milliseconds: 5), () => fired++);
      timer.cancel();
      expect(timer.endsAt, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(fired, 0);
    });

    test('a non-positive duration leaves the timer unchanged', () {
      final timer = SleepTimer();
      timer.start(Duration.zero, () {});
      expect(timer.endsAt, isNull);
    });
  });

  group('AudioInterruptionPolicy', () {
    test('a transient pause resumes when focus returns', () {
      final policy = AudioInterruptionPolicy();
      expect(policy.begin(isDuck: false, wasPlaying: true), isTrue);
      expect(policy.active, isTrue);
      expect(
        policy.end(isDuck: false, isPause: true, blocksPlayback: false),
        isTrue,
      );
      expect(policy.active, isFalse);
    });

    test('an interruption that began while paused does not resume', () {
      final policy = AudioInterruptionPolicy();
      expect(policy.begin(isDuck: false, wasPlaying: false), isTrue);
      expect(
        policy.end(isDuck: false, isPause: true, blocksPlayback: false),
        isFalse,
      );
    });

    test('ducking neither pauses nor resumes', () {
      final policy = AudioInterruptionPolicy();
      expect(policy.begin(isDuck: true, wasPlaying: true), isFalse);
      expect(policy.active, isFalse);
      expect(
        policy.end(isDuck: true, isPause: false, blocksPlayback: false),
        isFalse,
      );
    });

    test('automation that blocks playback prevents the resume', () {
      final policy = AudioInterruptionPolicy();
      policy.begin(isDuck: false, wasPlaying: true);
      expect(
        policy.end(isDuck: false, isPause: true, blocksPlayback: true),
        isFalse,
      );
    });

    test('a lost route forgets the pending resume', () {
      final policy = AudioInterruptionPolicy();
      policy.begin(isDuck: false, wasPlaying: true);
      policy.clearPending();
      expect(
        policy.end(isDuck: false, isPause: true, blocksPlayback: false),
        isFalse,
      );
    });
  });
}
