import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/library/library_scan_progress.dart';
import 'package:sistrum/services/native/native_channel.dart';

const _progressStream = EventChannel(
  'com.amwolfstein.sistrum/library_scan_progress_stream',
);

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('readLibraryScanProgress', () {
    Map<String, dynamic> snapshot({
      Object? pct = 42.456,
      Object? file = '/music/a.flac',
      Object? total = 10,
      Object? scanned = 4,
      Object? errors = 1,
      Object? complete,
    }) => {
      'progress_pct': ?pct,
      'current_file': ?file,
      'total_files': ?total,
      'scanned_files': ?scanned,
      'error_count': ?errors,
      'is_complete': ?complete,
    };

    LibraryScanProgressSample? read(
      Map<String, dynamic> progress, {
      bool cancelRequested = false,
      bool isScanning = true,
      bool isFinalizing = false,
    }) => readLibraryScanProgress(
      cancelRequested: cancelRequested,
      isScanning: isScanning,
      isFinalizing: isFinalizing,
      progress: progress,
    );

    test('maps a running snapshot and rounds progress to one decimal', () {
      final sample = read(snapshot())!;

      expect(sample.progress, 42.5);
      expect(sample.displayProgress, 42.5);
      expect(sample.currentFile, '/music/a.flac');
      expect(sample.totalFiles, 10);
      expect(sample.scannedFiles, 4);
      expect(sample.errorCount, 1);
    });

    test('a finished-looking 100 percent still reads as 99 on screen', () {
      final sample = read(snapshot(pct: 99.96))!;

      expect(sample.progress, 100.0);
      expect(sample.displayProgress, 99.0);
    });

    test('progress is clamped to the 0 to 100 range', () {
      expect(read(snapshot(pct: 150))!.progress, 100.0);
      expect(read(snapshot(pct: -5))!.progress, 0.0);
      expect(read(snapshot(pct: 50))!.progress, 50.0);
    });

    test('missing fields fall back to empty defaults', () {
      final sample = read({})!;

      expect(sample.progress, 0.0);
      expect(sample.displayProgress, 0.0);
      expect(sample.currentFile, isNull);
      expect(sample.totalFiles, 0);
      expect(sample.scannedFiles, 0);
      expect(sample.errorCount, 0);
    });

    test('returns null when the snapshot must not move the state', () {
      expect(read(snapshot(), cancelRequested: true), isNull);
      expect(read(snapshot(), isScanning: false), isNull);
      expect(read(snapshot(), isFinalizing: true), isNull);
      expect(read(snapshot(complete: true)), isNull);
    });

    test('a wrong-typed native field is treated as absent, not a crash', () {
      final sample = read(
        snapshot(file: 7, total: 'ten', scanned: true, errors: [1]),
      );

      expect(sample, isNotNull);
      expect(sample!.currentFile, isNull);
      expect(sample.totalFiles, 0);
      expect(sample.scannedFiles, 0);
      expect(sample.errorCount, 0);
    });
  });

  group('LibraryScanProgressPolling', () {
    late int polls;
    late List<Map<String, dynamic>> progressSeen;
    late List<String> warnings;

    setUp(() {
      polls = 0;
      progressSeen = [];
      warnings = [];
      _messenger.setMockMethodCallHandler(nativeBackendChannel, (call) async {
        if (call.method == 'getLibraryScanProgress') {
          polls++;
          return {'progress_pct': 10.0, 'scanned_files': polls};
        }
        return null;
      });
      _messenger.setMockStreamHandler(
        _progressStream,
        MockStreamHandler.inline(onListen: (arguments, events) {}),
      );
    });

    tearDown(() {
      _messenger.setMockMethodCallHandler(nativeBackendChannel, null);
      _messenger.setMockStreamHandler(_progressStream, null);
    });

    LibraryScanProgressPolling newPolling() => LibraryScanProgressPolling(
      onProgress: (progress) async => progressSeen.add(progress),
      onWarning: warnings.add,
    );

    test('polling mode fetches repeatedly until stopped', () async {
      final polling = newPolling()..start(useStream: false);

      await Future<void>.delayed(const Duration(milliseconds: 1000));
      expect(polls, greaterThanOrEqualTo(2));
      expect(progressSeen, isNotEmpty);
      expect(progressSeen.first['progress_pct'], 10.0);

      polling.stop();
      final afterStop = polls;
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(polls, afterStop);
      expect(warnings, isEmpty);
    });

    test('stream mode takes one immediate poll and no timer polls', () async {
      _messenger.setMockStreamHandler(
        _progressStream,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            Future<void>.delayed(
              const Duration(milliseconds: 20),
              () => events.success({'progress_pct': 5.0}),
            );
          },
        ),
      );
      final polling = newPolling()..start(useStream: true);

      await Future<void>.delayed(const Duration(milliseconds: 1000));
      polling.stop();

      expect(polls, 1);
      expect(progressSeen.any((p) => p['progress_pct'] == 5.0), isTrue);
      // The stream delivered an event, so no bootstrap-timeout warning.
      expect(warnings, isEmpty);
    });

    test(
      'stop before the bootstrap timeout reports no timeout warning',
      () async {
        _messenger.setMockStreamHandler(
          _progressStream,
          MockStreamHandler.inline(onListen: (arguments, events) {}),
        );
        final polling = newPolling()..start(useStream: true);

        await Future<void>.delayed(const Duration(milliseconds: 100));
        polling.stop();
        await Future<void>.delayed(const Duration(milliseconds: 1000));

        expect(warnings.where((w) => w.contains('timeout')), isEmpty);
      },
    );
  });
}
