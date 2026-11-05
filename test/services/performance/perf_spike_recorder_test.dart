import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/performance/perf_spike_recorder.dart';

const _normalUs = 10000; // well inside a 16.67 ms budget
const _overUs = 30000; // over budget

/// Feeds one frame. Frames are 16 ms apart on the engine clock.
void _frame(PerfSpikeRecorder r, {required bool over, required int index}) {
  r.onFrame(
    buildUs: 4000,
    rasterUs: over ? 26000 : 6000,
    spanUs: over ? _overUs : _normalUs,
    endUs: index * 16000,
  );
}

PerfSpikeRecorder _small({PerfSpikeContextReader? context}) {
  final r = PerfSpikeRecorder(
    preFrames: 10,
    postFrames: 5,
    windowFrames: 4,
    triggerOverBudget: 3,
    rearmOverBudget: 1,
    maxSnapshots: 2,
    maxEvents: 3,
  )..budgetUs = 16666;
  r.contextReader = context;
  return r;
}

void main() {
  test('normal frames never trigger a capture', () {
    final r = _small();
    for (var i = 0; i < 50; i++) {
      _frame(r, over: false, index: i);
    }
    expect(r.snapshots, isEmpty);
    expect(r.capturing, isFalse);
  });

  test('sustained over-budget frames capture the frames before and after', () {
    final r = _small();
    var i = 0;
    for (; i < 4; i++) {
      _frame(r, over: false, index: i);
    }
    // Three over-budget frames in the 4-frame window trigger the capture.
    for (var k = 0; k < 3; k++) {
      _frame(r, over: true, index: i++);
    }
    expect(r.capturing, isTrue);
    expect(r.snapshots, isEmpty, reason: 'post frames are still due');

    for (var k = 0; k < 5; k++) {
      _frame(r, over: true, index: i++);
    }
    expect(r.capturing, isFalse);
    expect(r.snapshots, hasLength(1));

    final snap = r.snapshots.single;
    // Seven frames were seen before the trigger (4 normal + 3 over).
    expect(snap.preSegment.frames, 7);
    expect(snap.preSegment.exceedancePct, closeTo(300 / 7, 0.01));
    expect(snap.postSegment.frames, 5);
    expect(snap.postSegment.exceedancePct, 100);
    expect(snap.preSegment.rasterP90Ms, closeTo(26, 0.01));
    expect(snap.postSegment.buildP50Ms, closeTo(4, 0.01));
  });

  test('the recorder re-arms only after the window recovers', () {
    final r = _small();
    var i = 0;
    void over(int n) {
      for (var k = 0; k < n; k++) {
        _frame(r, over: true, index: i++);
      }
    }

    void normal(int n) {
      for (var k = 0; k < n; k++) {
        _frame(r, over: false, index: i++);
      }
    }

    over(9); // trigger at frame 4, then 5 post frames: one snapshot
    expect(r.snapshots, hasLength(1));

    over(10); // still degraded: disarmed, so no second snapshot
    expect(r.snapshots, hasLength(1));

    normal(4); // window recovers to 0 over-budget, which re-arms
    over(3); // a new sustained spike
    over(5); // its post frames
    expect(r.snapshots, hasLength(2));
  });

  test('stored snapshots are bounded and the oldest is dropped', () {
    final r = _small();
    var i = 0;
    for (var cycle = 0; cycle < 3; cycle++) {
      for (var k = 0; k < 3; k++) {
        _frame(r, over: true, index: i++);
      }
      for (var k = 0; k < 5; k++) {
        _frame(r, over: true, index: i++);
      }
      for (var k = 0; k < 4; k++) {
        _frame(r, over: false, index: i++);
      }
    }
    expect(r.snapshots, hasLength(2));
  });

  test('reset clears an in-flight capture without a snapshot', () {
    final r = _small();
    for (var i = 0; i < 4; i++) {
      _frame(r, over: false, index: i);
    }
    for (var i = 4; i < 7; i++) {
      _frame(r, over: true, index: i);
    }
    expect(r.capturing, isTrue);
    r.reset();
    expect(r.capturing, isFalse);
    for (var i = 7; i < 30; i++) {
      _frame(r, over: true, index: i);
    }
    // A new run starts armed, so a later spike is captured normally.
    expect(r.snapshots, hasLength(1));
  });

  test('events inside the captured span are kept, bounded by maxEvents', () {
    final r = _small();
    var i = 0;
    for (; i < 2; i++) {
      _frame(r, over: false, index: i);
    }
    r.noteEvent('renderer=New Full Glass');
    r.noteEvent('scene=D');
    r.noteEvent('speed=fast');
    r.noteEvent('app_lifecycle=paused'); // evicts the oldest (maxEvents 3)
    for (; i < 8; i++) {
      _frame(r, over: true, index: i);
    }
    for (var k = 0; k < 5; k++) {
      _frame(r, over: true, index: i++);
    }
    final events = r.snapshots.single.events.join('\n');
    expect(events, isNot(contains('renderer=New Full Glass')));
    expect(events, contains('scene=D'));
    expect(events, contains('speed=fast'));
    expect(events, contains('app_lifecycle=paused'));
  });

  test('the context is read once per spike and stored with it', () {
    var reads = 0;
    final r = _small(
      context: () {
        reads++;
        return {
          'glass_mode': 'New Full Glass',
          'glass_render_path': 'full_gpu',
        };
      },
    );
    var i = 0;
    for (var k = 0; k < 4; k++) {
      _frame(r, over: true, index: i++);
    }
    for (var k = 0; k < 5; k++) {
      _frame(r, over: true, index: i++);
    }
    expect(reads, 1, reason: 'read at trigger time only');
    expect(r.snapshots.single.context['glass_render_path'], 'full_gpu');
  });

  test('the text report names every section of the spike', () {
    final r = _small();
    var i = 0;
    for (var k = 0; k < 4; k++) {
      _frame(r, over: true, index: i++);
    }
    for (var k = 0; k < 5; k++) {
      _frame(r, over: true, index: i++);
    }
    final text = r.snapshots.single.toText();
    expect(text, contains('spike wall_clock='));
    expect(text, contains('spike duration_ms='));
    expect(text, contains('spike_pre frames=4'));
    expect(text, contains('spike_post frames=5'));
    expect(text, contains('spike_interval_ms='));
    expect(text, contains('raster_ms_p90='));
  });

  test('frame intervals are bucketed by frame end time', () {
    final r = _small();
    var i = 0;
    for (var k = 0; k < 4; k++) {
      _frame(r, over: true, index: i++);
    }
    for (var k = 0; k < 5; k++) {
      _frame(r, over: true, index: i++);
    }
    // Frames are 16 ms apart. The pre segment (4 frames) gives 3 intervals and
    // the post segment (5 frames) gives 4, all in the first (<= 17 ms) bucket.
    final snap = r.snapshots.single;
    expect(snap.intervalCounts.first, 7);
    expect(snap.intervalCounts.skip(1).every((c) => c == 0), isTrue);
  });
}
