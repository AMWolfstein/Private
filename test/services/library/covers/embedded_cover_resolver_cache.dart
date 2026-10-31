part of 'embedded_cover_resolver_test.dart';

void _registerEmbeddedCoverResolverCache() {
  test('legacy NUL-prefixed JPEG previews are re-extracted', () async {
    final sourcePath = await _createAudioFixture('legacy-padded-cover');
    var extractions = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backendChannel, (call) async {
          if (mediaScopeMethods.contains(call.method)) return '';
          expect(call.method, 'extractCoverToFile');
          extractions++;
          await File(
            (call.arguments as Map)['output_path'] as String,
          ).writeAsBytes([0xff, 0xd8, 0xff, 0xe0]);
          return jsonEncode({'success': true});
        });
    final preview = (await EmbeddedCoverResolver.resolveOrExtract(sourcePath))!;
    await File(preview).writeAsBytes([0, 0xff, 0xd8, 0xff, 0xe0]);
    await EmbeddedCoverResolver.resetMemoryStateForTesting();
    final refreshed = await EmbeddedCoverResolver.resolveOrExtract(sourcePath);
    expect(extractions, 2);
    expect(await File(refreshed!).readAsBytes(), [0xff, 0xd8, 0xff, 0xe0]);
  });

  test(
    'legacy SAF thumbnails are replaced without changing the audio',
    () async {
      const source = 'content://covers/document/original-artwork.flac';
      sourcePaths.add(source);
      var extractions = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(backendChannel, (call) async {
            if (mediaScopeMethods.contains(call.method)) return '';
            if (call.method == 'getSafFileModTimes') {
              return jsonEncode({source: 1234});
            }
            expect(call.method, 'extractCoverToFile');
            extractions++;
            await File(
              (call.arguments as Map)['output_path'] as String,
            ).writeAsBytes([1, 2, 3]);
            return jsonEncode({'success': true});
          });
      final preview = (await EmbeddedCoverResolver.resolveOrExtract(source))!;
      await EmbeddedCoverResolver.resetMemoryStateForTesting();
      final legacy = preview.replaceFirst('v2_', 'v1_');
      expect(legacy, isNot(preview));
      await File(preview).rename(legacy);
      await File('$preview.source').rename('$legacy.source');
      await File(legacy).writeAsBytes([8, 0, 0]);

      final refreshed = await EmbeddedCoverResolver.resolveOrExtract(source);
      expect(extractions, 2);
      expect(await File(refreshed!).readAsBytes(), [1, 2, 3]);
      await EmbeddedCoverResolver.runPersistentCacheMaintenanceForTesting();
      expect(await File(legacy).exists(), isFalse);
      expect(await File('$legacy.source').exists(), isFalse);
    },
  );

  test('persistent maintenance enforces entry and byte caps', () async {
    final paths = await Future.wait([
      for (var index = 0; index < 3; index++)
        _createAudioFixture('persistent-cap-$index'),
    ]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backendChannel, (call) async {
          if (mediaScopeMethods.contains(call.method)) return '';
          final arguments = call.arguments as Map<Object?, Object?>;
          await File(
            arguments['output_path']! as String,
          ).writeAsBytes(const [25, 26, 27, 28]);
          return jsonEncode({'success': true});
        });

    final previews = <String>[];
    for (final path in paths) {
      previews.add((await EmbeddedCoverResolver.resolveOrExtract(path))!);
    }
    await EmbeddedCoverResolver.resetMemoryStateForTesting();
    for (var index = 0; index < previews.length; index++) {
      await File(previews[index]).setLastModified(DateTime(2024, 1, index + 1));
    }

    await EmbeddedCoverResolver.runPersistentCacheMaintenanceForTesting(
      maxEntries: 2,
      maxBytes: 100,
      targetBytes: 100,
    );
    expect(await File(previews[0]).exists(), isFalse);
    expect(await File(previews[1]).exists(), isTrue);
    expect(await File(previews[2]).exists(), isTrue);

    await EmbeddedCoverResolver.runPersistentCacheMaintenanceForTesting(
      maxEntries: 10,
      maxBytes: 5,
      targetBytes: 4,
    );
    final survivors = await Future.wait([
      for (final preview in previews) File(preview).exists(),
    ]);
    expect(survivors.where((exists) => exists), hasLength(1));
  });

  test(
    'persistent cache clear waits for cancelled native extraction cleanup',
    () async {
      final sourcePath = await _createAudioFixture('clear-in-flight');
      final started = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(backendChannel, (call) async {
            if (mediaScopeMethods.contains(call.method)) return '';
            if (!started.isCompleted) started.complete();
            await release.future;
            final arguments = call.arguments as Map<Object?, Object?>;
            await File(
              arguments['output_path']! as String,
            ).writeAsBytes(const [29, 30, 31]);
            return jsonEncode({'success': true});
          });

      final resolution = EmbeddedCoverResolver.resolveOrExtract(sourcePath);
      await started.future.timeout(const Duration(seconds: 2));
      var clearCompleted = false;
      final clear = EmbeddedCoverResolver.clearPersistentCache().then(
        (_) => clearCompleted = true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(clearCompleted, isFalse);

      release.complete();
      expect(await resolution, isNull);
      await clear.timeout(const Duration(seconds: 2));
      expect(clearCompleted, isTrue);
      expect(await persistentCacheDirectory.list().toList(), isEmpty);
    },
  );
}
