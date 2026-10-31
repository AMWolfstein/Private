part of 'embedded_cover_resolver_test.dart';

const backendChannel = MethodChannel('com.amwolfstein.sistrum/backend');

// Media-directory scopes wrap every file call; these tests assert cover work.
const mediaScopeMethods = {'acquireMediaDirectory', 'releaseMediaDirectory'};

final sourcePaths = <String>[];

final tempDirectories = <Directory>[];

late Directory persistentCacheDirectory;

Future<String> _createAudioFixture(String name) async {
  final directory = await Directory.systemTemp.createTemp(
    'embedded_cover_resolver_test_',
  );
  tempDirectories.add(directory);
  final source = File('${directory.path}${Platform.pathSeparator}$name.flac');
  await source.writeAsBytes(const [0, 1, 2, 3]);
  sourcePaths.add(source.path);
  return source.path;
}

void _registerEmbeddedCoverResolver1() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    persistentCacheDirectory = await Directory.systemTemp.createTemp(
      'embedded_cover_persistent_test_',
    );
    EmbeddedCoverResolver.setPersistentCacheDirectoryForTesting(
      persistentCacheDirectory,
    );
  });

  tearDown(() async {
    await EmbeddedCoverResolver.resetMemoryStateForTesting(
      preservePersistentFiles: false,
    );
    EmbeddedCoverResolver.setPersistentCacheDirectoryForTesting(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backendChannel, null);
    sourcePaths.clear();
    for (final directory in tempDirectories) {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
    tempDirectories.clear();
    if (await persistentCacheDirectory.exists()) {
      await persistentCacheDirectory.delete(recursive: true);
    }
  });

  for (final saf in [false, true]) {
    test(
      'a temporarily unavailable cover retries after cooldown (SAF=$saf)',
      () async {
        final source = saf
            ? 'content://example.documents/tree/nas/document/song.flac'
            : await _createAudioFixture('temporarily-unavailable');
        var now = DateTime(2026, 10, 3);
        EmbeddedCoverResolver.setValidationClockForTesting(() => now);
        var extractions = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(backendChannel, (call) async {
              if (mediaScopeMethods.contains(call.method)) return '';
              if (call.method == 'getSafFileModTimes') {
                return jsonEncode({source: 1234});
              }
              expect(call.method, 'extractCoverToFile');
              extractions++;
              if (extractions == 1) {
                return jsonEncode({
                  'error': 'Provider temporarily unavailable',
                });
              }
              final args = call.arguments as Map<Object?, Object?>;
              await File(
                args['output_path']! as String,
              ).writeAsBytes([4, 5, 6]);
              return jsonEncode({'success': true});
            });
        expect(await EmbeddedCoverResolver.resolveOrExtract(source), isNull);
        for (var i = 0; i < 5; i++) {
          expect(await EmbeddedCoverResolver.resolveOrExtract(source), isNull);
        }
        expect(extractions, 1);
        now = now.add(const Duration(seconds: 31));
        final recovered = await EmbeddedCoverResolver.resolveOrExtract(source);
        expect(recovered, isNotNull);
        expect(await File(recovered!).readAsBytes(), [4, 5, 6]);
        expect(extractions, 2);
        expect(await EmbeddedCoverResolver.resolveOrExtract(source), recovered);
        expect(extractions, 2);
      },
    );
  }

  test(
    'cold resolve starts extraction and reports the cached preview',
    () async {
      final sourcePath = await _createAudioFixture('cold-cache');
      var extractionCalls = 0;
      final changed = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(backendChannel, (call) async {
            if (mediaScopeMethods.contains(call.method)) return '';
            expect(call.method, 'extractCoverToFile');
            extractionCalls++;
            final arguments = call.arguments as Map<Object?, Object?>;
            await File(
              arguments['output_path']! as String,
            ).writeAsBytes(const [4, 5, 6]);
            return jsonEncode({'success': true});
          });

      final initial = EmbeddedCoverResolver.resolve(
        sourcePath,
        onChanged: () {
          if (!changed.isCompleted) changed.complete();
        },
      );

      expect(initial, isNull);
      await changed.future.timeout(const Duration(seconds: 2));
      final cached = EmbeddedCoverResolver.resolve(sourcePath);
      expect(extractionCalls, 1);
      expect(cached, isNotNull);
      expect(await File(cached!).exists(), isTrue);
    },
  );

  test('concurrent resolveOrExtract calls share one extraction', () async {
    final sourcePath = await _createAudioFixture('concurrent');
    var extractionCalls = 0;
    var callbacks = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backendChannel, (call) async {
          if (mediaScopeMethods.contains(call.method)) return '';
          expect(call.method, 'extractCoverToFile');
          extractionCalls++;
          final arguments = call.arguments as Map<Object?, Object?>;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await File(
            arguments['output_path']! as String,
          ).writeAsBytes(const [7, 8, 9]);
          return jsonEncode({'success': true});
        });

    final results = await Future.wait([
      EmbeddedCoverResolver.resolveOrExtract(
        sourcePath,
        onChanged: () => callbacks++,
      ),
      EmbeddedCoverResolver.resolveOrExtract(
        sourcePath,
        onChanged: () => callbacks++,
      ),
      EmbeddedCoverResolver.resolveOrExtract(
        sourcePath,
        onChanged: () => callbacks++,
      ),
    ]);

    expect(extractionCalls, 1);
    expect(callbacks, 3);
    expect(results.toSet(), hasLength(1));
    expect(results.first, isNotNull);
    expect(await File(results.first!).exists(), isTrue);
  });

  test(
    'background cover extraction is limited to two concurrent jobs',
    () async {
      final paths = await Future.wait([
        for (var index = 0; index < 5; index++)
          _createAudioFixture('bounded-$index'),
      ]);
      final release = Completer<void>();
      final firstTwoStarted = Completer<void>();
      final allCompleted = Completer<void>();
      var calls = 0;
      var active = 0;
      var maxActive = 0;
      var completed = 0;
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(backendChannel, (call) async {
            if (mediaScopeMethods.contains(call.method)) return '';
            expect(call.method, 'extractCoverToFile');
            calls++;
            active++;
            if (active > maxActive) maxActive = active;
            if (calls == 2 && !firstTwoStarted.isCompleted) {
              firstTwoStarted.complete();
            }
            try {
              await release.future;
              final arguments = call.arguments as Map<Object?, Object?>;
              await File(
                arguments['output_path']! as String,
              ).writeAsBytes(const [13, 14, 15]);
              return jsonEncode({'success': true});
            } finally {
              active--;
            }
          });

      void onChanged() {
        completed++;
        if (completed == paths.length && !allCompleted.isCompleted) {
          allCompleted.complete();
        }
      }

      for (final path in paths) {
        expect(
          EmbeddedCoverResolver.resolve(path, onChanged: onChanged),
          isNull,
        );
      }

      await firstTwoStarted.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, 2);
      expect(maxActive, 2);

      release.complete();
      await allCompleted.future.timeout(const Duration(seconds: 2));
      expect(calls, paths.length);
      expect(maxActive, 2);
    },
  );

  test(
    'validation shares callbacks and detects external changes after interval',
    () async {
      var now = DateTime.utc(2026);
      EmbeddedCoverResolver.setValidationClockForTesting(() => now);
      const path = 'content://covers/document/external';
      var modTime = 1234;
      var extractions = 0;
      var modTimeCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(backendChannel, (call) async {
            if (mediaScopeMethods.contains(call.method)) return '';
            if (call.method == 'getSafFileModTimes') {
              modTimeCalls++;
              return jsonEncode({path: modTime});
            }
            expect(call.method, 'extractCoverToFile');
            extractions++;
            await File(
              (call.arguments as Map)['output_path'] as String,
            ).writeAsBytes([1, 2, 3]);
            return jsonEncode({'success': true});
          });
      await EmbeddedCoverResolver.resolveOrExtract(path);
      EmbeddedCoverResolver.resolve(path);
      await EmbeddedCoverResolver.waitForPreviewValidationForTesting();
      modTime = 5678;
      EmbeddedCoverResolver.resolve(path);
      await EmbeddedCoverResolver.waitForPreviewValidationForTesting();
      expect(extractions, 1);
      expect(modTimeCalls, 2);
      now = now.add(const Duration(seconds: 5));
      var firstNotified = 0;
      var secondNotified = 0;
      EmbeddedCoverResolver.resolve(path, onChanged: () => firstNotified++);
      EmbeddedCoverResolver.resolve(path, onChanged: () => secondNotified++);
      await EmbeddedCoverResolver.waitForPreviewValidationForTesting();
      expect(extractions, 2);
      expect(firstNotified, 1);
      expect(secondNotified, 1);
    },
  );

  test('foreground extraction is promoted ahead of background jobs', () async {
    final paths = await Future.wait([
      for (var index = 0; index < 4; index++)
        _createAudioFixture('priority-$index'),
    ]);
    final releaseFirst = Completer<void>();
    final releaseSecond = Completer<void>();
    final firstTwoStarted = Completer<void>();
    final thirdStarted = Completer<void>();
    final allCompleted = Completer<void>();
    final startedPaths = <String>[];
    var completed = 0;
    addTearDown(() {
      if (!releaseFirst.isCompleted) releaseFirst.complete();
      if (!releaseSecond.isCompleted) releaseSecond.complete();
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backendChannel, (call) async {
          if (mediaScopeMethods.contains(call.method)) return '';
          expect(call.method, 'extractCoverToFile');
          final arguments = call.arguments as Map<Object?, Object?>;
          final audioPath = arguments['audio_path']! as String;
          startedPaths.add(audioPath);
          final callIndex = startedPaths.length - 1;
          if (startedPaths.length == 2 && !firstTwoStarted.isCompleted) {
            firstTwoStarted.complete();
          }
          if (startedPaths.length == 3 && !thirdStarted.isCompleted) {
            thirdStarted.complete();
          }
          if (callIndex == 0) {
            await releaseFirst.future;
          } else if (callIndex == 1) {
            await releaseSecond.future;
          }
          await File(
            arguments['output_path']! as String,
          ).writeAsBytes(const [16, 17, 18]);
          return jsonEncode({'success': true});
        });

    void onChanged() {
      completed++;
      if (completed == paths.length && !allCompleted.isCompleted) {
        allCompleted.complete();
      }
    }

    EmbeddedCoverResolver.resolve(paths[0], onChanged: onChanged);
    EmbeddedCoverResolver.resolve(paths[1], onChanged: onChanged);
    await firstTwoStarted.future.timeout(const Duration(seconds: 2));

    EmbeddedCoverResolver.resolve(paths[2], onChanged: onChanged);
    EmbeddedCoverResolver.resolve(paths[3], onChanged: onChanged);
    final foreground = EmbeddedCoverResolver.resolveOrExtract(paths[3]);

    releaseFirst.complete();
    await thirdStarted.future.timeout(const Duration(seconds: 2));
    expect(startedPaths[2], paths[3]);

    releaseSecond.complete();
    expect(await foreground, isNotNull);
    await allCompleted.future.timeout(const Duration(seconds: 2));
    expect(startedPaths, hasLength(paths.length));
  });

  test(
    'persistent preview survives memory reset and revalidates source changes',
    () async {
      final sourcePath = await _createAudioFixture('persistent-restart');
      var extractionCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(backendChannel, (call) async {
            if (mediaScopeMethods.contains(call.method)) return '';
            expect(call.method, 'extractCoverToFile');
            extractionCalls++;
            final arguments = call.arguments as Map<Object?, Object?>;
            await File(
              arguments['output_path']! as String,
            ).writeAsBytes([extractionCalls, 20, 21]);
            return jsonEncode({'success': true});
          });

      final first = await EmbeddedCoverResolver.resolveOrExtract(sourcePath);
      expect(first, isNotNull);
      expect(extractionCalls, 1);

      await EmbeddedCoverResolver.resetMemoryStateForTesting();
      final reused = await EmbeddedCoverResolver.resolveOrExtract(sourcePath);
      expect(reused, first);
      expect(extractionCalls, 1);

      await File(sourcePath).writeAsBytes(const [9, 8, 7, 6, 5]);
      await File(
        sourcePath,
      ).setLastModified(DateTime.now().add(const Duration(seconds: 2)));
      await EmbeddedCoverResolver.resetMemoryStateForTesting();

      final refreshed = await EmbeddedCoverResolver.resolveOrExtract(
        sourcePath,
      );
      expect(extractionCalls, 2);
      expect(refreshed, isNotNull);
      expect(refreshed, isNot(first));
      expect(await File(refreshed!).exists(), isTrue);
      expect(await File(first!).exists(), isFalse);
    },
  );
}
