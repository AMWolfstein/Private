import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/library/scan/library_scan_notifications.dart';
import 'package:sistrum/services/platform/notification_service.dart';

class _FakeNotifications implements NotificationService {
  final calls = <String>[];

  /// Notices whose call should fail, by method name.
  final failing = <String>{};

  Future<void> _record(String call, String name) async {
    calls.add(call);
    if (failing.contains(name)) throw StateError('$name failed');
  }

  @override
  Future<void> showLibraryScanProgress({
    required double progress,
    required int scannedFiles,
    required int totalFiles,
    String? currentFile,
  }) => _record(
    'progress:${progress.toStringAsFixed(1)}:$scannedFiles:$totalFiles:'
        '${currentFile ?? '-'}',
    'progress',
  );

  @override
  Future<void> showLibraryScanComplete({
    required int totalTracks,
    int errorCount = 0,
  }) => _record('complete:$totalTracks:$errorCount', 'complete');

  @override
  Future<void> showLibraryScanFailed(String message) =>
      _record('failed:$message', 'failed');

  @override
  Future<void> showLibraryScanCancelled() => _record('cancelled', 'cancelled');

  @override
  Future<void> showLibraryScanPaused({required int scannedFiles}) =>
      _record('paused:$scannedFiles', 'paused');

  @override
  Future<void> cancelLibraryScanNotification() => _record('cancel', 'cancel');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeNotifications service;
  late bool progressVisible;
  late LibraryScanNotifications notifications;

  setUp(() {
    service = _FakeNotifications();
    progressVisible = true;
    notifications = LibraryScanNotifications(
      service: service,
      progressVisible: () => progressVisible,
    );
  });

  group('shouldShowProgress throttling', () {
    test('shows the first snapshot and then only real changes', () {
      expect(
        notifications.shouldShowProgress(
          progress: 10,
          totalFiles: 50,
          isComplete: false,
        ),
        isTrue,
      );
      // Same rounded percent, same total, no completion, no heartbeat yet.
      expect(
        notifications.shouldShowProgress(
          progress: 10.2,
          totalFiles: 50,
          isComplete: false,
        ),
        isFalse,
      );
      // A new rounded percent shows again.
      expect(
        notifications.shouldShowProgress(
          progress: 10.6,
          totalFiles: 50,
          isComplete: false,
        ),
        isTrue,
      );
      // A changed file total shows even at the same percent.
      expect(
        notifications.shouldShowProgress(
          progress: 11,
          totalFiles: 51,
          isComplete: false,
        ),
        isTrue,
      );
    });

    test('completion always shows, and reset makes the next snapshot show', () {
      notifications.shouldShowProgress(
        progress: 80,
        totalFiles: 5,
        isComplete: false,
      );
      expect(
        notifications.shouldShowProgress(
          progress: 80,
          totalFiles: 5,
          isComplete: true,
        ),
        isTrue,
      );

      notifications.reset();
      expect(
        notifications.shouldShowProgress(
          progress: 80,
          totalFiles: 5,
          isComplete: false,
        ),
        isTrue,
      );
    });

    test(
      'a heartbeat shows an unchanged snapshot after four seconds',
      () async {
        notifications.shouldShowProgress(
          progress: 30,
          totalFiles: 5,
          isComplete: false,
        );
        await Future<void>.delayed(const Duration(milliseconds: 4100));

        expect(
          notifications.shouldShowProgress(
            progress: 30,
            totalFiles: 5,
            isComplete: false,
          ),
          isTrue,
        );
      },
    );
  });

  group('notices', () {
    test('each notice reaches its service call with its arguments', () async {
      await notifications.showPaused(7);
      await notifications.cancelPaused();
      await notifications.showProgress(
        progress: 42,
        scannedFiles: 3,
        totalFiles: 9,
        currentFile: '/music/Artist/Track.flac',
      );
      await notifications.showComplete(totalTracks: 120, errorCount: 2);
      await notifications.showFailed('disk full');
      await notifications.showCancelled();

      expect(service.calls, [
        'paused:7',
        'cancel',
        'progress:42.0:3:9:Track.flac',
        'complete:120:2',
        'failed:disk full',
        'cancelled',
      ]);
    });

    test('progress notices are suppressed once progress is hidden', () async {
      progressVisible = false;

      await notifications.showProgress(
        progress: 10,
        scannedFiles: 1,
        totalFiles: 2,
        currentFile: null,
      );

      expect(service.calls, isEmpty);
    });

    test(
      'a failing notice is logged and does not stop later notices',
      () async {
        service.failing.add('complete');

        await expectLater(
          notifications.showComplete(totalTracks: 1, errorCount: 0),
          completes,
        );
        await notifications.showCancelled();

        expect(service.calls, ['complete:1:0', 'cancelled']);
      },
    );

    test(
      'queued notices run one at a time, in the order they were requested',
      () async {
        final order = <String>[];
        Future<void> slow(String name) => notifications.queue(() async {
          order.add('start $name');
          await Future<void>.delayed(const Duration(milliseconds: 30));
          order.add('end $name');
        });

        final first = slow('a');
        final second = slow('b');
        await Future.wait([first, second, notifications.pending]);

        expect(order, ['start a', 'end a', 'start b', 'end b']);
      },
    );

    test('pending completes after every queued notice was attempted', () async {
      service.failing.add('failed');
      unawaited(notifications.showFailed('boom'));
      unawaited(notifications.showCancelled());

      await notifications.pending;

      expect(service.calls, ['failed:boom', 'cancelled']);
    });
  });

  group('shortenFile', () {
    test('returns null for missing or blank paths', () {
      expect(LibraryScanNotifications.shortenFile(null), isNull);
      expect(LibraryScanNotifications.shortenFile(''), isNull);
      expect(LibraryScanNotifications.shortenFile('   '), isNull);
    });

    test('keeps only the last segment of slash and backslash paths', () {
      expect(
        LibraryScanNotifications.shortenFile('/music/Artist/Song.mp3'),
        'Song.mp3',
      );
      expect(
        LibraryScanNotifications.shortenFile(r'C:\Music\Artist\Song.flac'),
        'Song.flac',
      );
    });

    test('decodes percent-encoded names before shortening', () {
      expect(
        LibraryScanNotifications.shortenFile('/music/My%20Song.mp3'),
        'My Song.mp3',
      );
    });

    test('keeps an invalid escape and a bare name as they are', () {
      expect(
        LibraryScanNotifications.shortenFile('/music/100%.mp3'),
        '100%.mp3',
      );
      expect(LibraryScanNotifications.shortenFile('  song.mp3  '), 'song.mp3');
    });
  });
}
