part of 'music_player_runtime_test.dart';

void _registerMusicPlayerRuntime2() {
  test(
    'player learns explicit skips, excludes pauses and obeys live opt-out',
    () async {
      var elapsed = Duration.zero;
      final learning = AutoplayPersonalization(
        load: () async => null,
        save: (_) async {},
        elapsed: () => elapsed,
        now: () => DateTime(2026),
      );
      final runtime = _runtime(
        settings: const AppSettings(
          pauseOnMute: false,
          autoplayPersonalization: true,
        ),
        createPersonalization: () => learning,
      );
      final handler = await runtime.initialize();
      await learning.ensureLoaded();
      const second = PlayableMedia(
        id: 'two',
        source: '/two.flac',
        title: 'Two',
        artist: 'Other',
        duration: Duration(seconds: 60),
      );
      await handler.setQueueAndPlay([_track, second]);
      await _settle();
      elapsed += const Duration(seconds: 10);
      await handler.pause();
      elapsed += const Duration(hours: 1);
      await handler.play();
      await _settle();
      await handler.skipToNext();
      await _settle();
      expect(learning.observations, 1);
      expect(
        _adjustment(
          learning,
          const AutoplayLearningTrack(
            source: '/one.flac',
            title: 'One',
            artist: 'Artist',
            duration: Duration(seconds: 60),
          ),
          const AutoplayLearningTrack(
            source: '/two.flac',
            title: 'Two',
            artist: 'Other',
          ),
          DateTime(2026),
        ),
        lessThan(0),
      );
      elapsed += const Duration(seconds: 10);
      await handler.skipToQueueItem(
        1,
      ); // Restarting is not rejecting this song.
      await _settle();
      expect(learning.observations, 1);
      runtime.configure(
        runtime.settings.copyWith(autoplayPersonalization: false),
      );
      elapsed += const Duration(seconds: 50);
      await handler.skipToQueueItem(0);
      expect(learning.observations, 1);
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.mediaItem.value?.id, 'one');
    },
  );

  test(
    'muted start pauses and warns; explicit resume survives source reload',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'muted-playback-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = await File(
        '${directory.path}/song.flac',
      ).writeAsString('audio');
      final volume = StreamController<double>.broadcast();
      addTearDown(volume.close);
      final runtime = _runtime(
        settings: const AppSettings(pauseOnMute: true),
        volumeChanges: volume.stream,
      );
      var warnings = 0;
      final notices = runtime.mutedPlaybackEvents.listen((_) => warnings++);
      addTearDown(notices.cancel);
      final handler = await runtime.initialize();
      volume.add(0);
      await _settle();
      await handler.setQueueAndPlay([
        PlayableMedia(
          id: 'muted',
          source: file.path,
          title: 'Muted',
          artist: '',
        ),
      ]);
      await _settle();
      await _settle();
      expect(handler.mediaItem.value?.id, 'muted');
      expect(handler.playbackState.value.playing, isFalse);
      expect(warnings, 1);

      await handler.play();
      await _settle();
      expect(handler.playbackState.value.playing, isTrue);
      volume.add(0);
      await _settle();
      expect(handler.playbackState.value.playing, isTrue);
      expect(warnings, 1);

      volume.add(0.5);
      await _settle();
      volume.add(0);
      await _settle();
      await _settle();
      expect(handler.playbackState.value.playing, isFalse);
      expect(warnings, 2);
      await handler.pause();
      volume.add(0.5);
      await _settle();
      expect(handler.playbackState.value.playing, isFalse);
    },
  );

  test(
    'position ticks skip listening updates while flushes retain time',
    () async {
      var elapsed = Duration.zero;
      final writes = <ListeningDelta>[];
      final recorder = _Recorder(
        write: (batch) async => writes.addAll(batch),
        elapsed: () => elapsed,
        now: () => DateTime(2026, 10, 1, 23, 59, 50).add(elapsed),
      );
      final handler = await _runtime(recorder: recorder).initialize();
      handler.mediaItem.add(_item);
      handler.playbackState.add(
        PlaybackState(
          playing: true,
          processingState: AudioProcessingState.ready,
        ),
      );
      await _settle();
      final updates = recorder.updates;
      for (var tick = 1; tick <= 1200; tick++) {
        elapsed = Duration(milliseconds: tick * 500);
        handler.playbackState.add(
          handler.playbackState.value.copyWith(updatePosition: elapsed),
        );
        if (tick % 20 == 0) await recorder.flush();
      }
      await _settle();
      expect(recorder.updates, updates);
      expect(
        writes.fold<int>(0, (sum, delta) => sum + delta.milliseconds),
        600000,
      );
      expect(writes.fold<int>(0, (sum, delta) => sum + delta.plays), 1);
      expect(writes.first.day, '2026-10-01');
      expect(writes.first.milliseconds, 10000);
      expect(
        writes.skip(1).every((delta) => delta.day == '2026-10-02'),
        isTrue,
      );
    },
  );

  test(
    'listening transitions retain buffering, repeat and metadata semantics',
    () async {
      var elapsed = Duration.zero;
      final writes = <ListeningDelta>[];
      final recorder = _Recorder(
        write: (batch) async => writes.addAll(batch),
        elapsed: () => elapsed,
        now: () => DateTime(2026, 10, 1, 23, 59, 50).add(elapsed),
      );
      final handler = await _runtime(recorder: recorder).initialize();
      Future<void> state(bool playing, AudioProcessingState processing) async {
        handler.playbackState.add(
          handler.playbackState.value.copyWith(
            playing: playing,
            processingState: processing,
          ),
        );
        await _settle();
      }

      handler.mediaItem.add(_item);
      await state(true, AudioProcessingState.ready);
      elapsed += const Duration(seconds: 5);
      final beforeSeek = recorder.updates;
      handler.playbackState.add(
        handler.playbackState.value.copyWith(
          updatePosition: const Duration(minutes: 10),
        ),
      );
      await _settle();
      expect(recorder.updates, beforeSeek);
      await recorder.flush();
      await state(true, AudioProcessingState.buffering);
      elapsed += const Duration(seconds: 20);
      await state(false, AudioProcessingState.ready);
      await state(true, AudioProcessingState.ready);
      elapsed += const Duration(seconds: 25);
      await state(false, AudioProcessingState.ready);
      elapsed += const Duration(seconds: 10);
      await state(true, AudioProcessingState.ready);
      elapsed += const Duration(seconds: 10);
      await state(false, AudioProcessingState.ready);
      await state(false, AudioProcessingState.completed);
      await state(true, AudioProcessingState.ready);
      elapsed += const Duration(seconds: 35);
      await recorder.flush();
      final beforeMetadata = recorder.updates;
      handler.mediaItem.add(_item.copyWith(title: 'Revised', artist: 'Guest'));
      await _settle();
      expect(recorder.updates, beforeMetadata + 1);
      expect(recorder.latestTrack?.title, 'Revised');
      expect(recorder.latestTrack?.artist, 'Guest');
      elapsed += const Duration(seconds: 25);
      await recorder.flush();
      elapsed += const Duration(seconds: 5);
      await recorder.flush();
      handler.mediaItem.add(const MediaItem(id: 'two', title: 'Two'));
      await _settle();
      elapsed += const Duration(seconds: 10);
      await recorder.flush();
      final one = writes.where((delta) => delta.track.key == 'one').toList();
      // Playing: 0-5s, 25-50s, 60-70s, 70-105s, 105-130s, 130-135s = 105s.
      // Buffering (5-25s), the pause (50-60s) and the seek accrue nothing.
      expect(
        one.fold<int>(0, (sum, delta) => sum + delta.milliseconds),
        105000,
      );
      expect(one.fold<int>(0, (sum, delta) => sum + delta.plays), 2);
      expect(one.first.day, '2026-10-01');
      expect(one.first.milliseconds, 5000);
      expect(one.skip(1).every((delta) => delta.day == '2026-10-02'), isTrue);
      expect(writes.last.track.key, 'two');
      expect(writes.last.milliseconds, 10000);
      expect(writes.last.plays, 0);
    },
  );

  test(
    'deletion subscriptions follow handler ownership and scoped overrides',
    () async {
      final events = SourceDeletionEvents();
      late MusicPlayerRuntime first;
      late MusicPlayerRuntime second;
      first = _runtime(
        sourceDeletionEvents: events,
        initialize: (_) async => _DeletionHandler(first),
      );
      second = _runtime(
        sourceDeletionEvents: events,
        initialize: (_) async => _DeletionHandler(second),
      );
      late MusicPlayerRuntime isolated;
      isolated = _runtime(initialize: (_) async => _DeletionHandler(isolated));
      final firstHandler = await first.initialize() as _DeletionHandler;
      final secondHandler = await second.initialize() as _DeletionHandler;
      final isolatedHandler = await isolated.initialize() as _DeletionHandler;
      first.attach(firstHandler); // Reattaching must not subscribe twice.
      await events.publish('/one.flac');
      expect(firstHandler.deletedSources, ['/one.flac']);
      expect(secondHandler.deletedSources, ['/one.flac']);
      expect(isolatedHandler.deletedSources, isEmpty);
      await firstHandler.dispose();
      final replacement = await first.initialize() as _DeletionHandler;
      await events.publish('/two.flac');
      expect(firstHandler.deletedSources, ['/one.flac']);
      expect(replacement.deletedSources, ['/two.flac']);
      expect(secondHandler.deletedSources, ['/one.flac', '/two.flac']);
      await first.dispose();
      await second.dispose();
      await events.publish('/three.flac');
      expect(replacement.deletedSources, ['/two.flac']);
      expect(secondHandler.deletedSources, ['/one.flac', '/two.flac']);
    },
  );

  test(
    'storage deletion removes duplicates and advances every attached player',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'queued-deletion-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = await File(
        '${directory.path}/one.flac',
      ).writeAsString('audio');
      final events = SourceDeletionEvents();
      final runtimes = [
        _runtime(sourceDeletionEvents: events),
        _runtime(sourceDeletionEvents: events),
      ];
      final removed = PlayableMedia(
        id: 'removed',
        source: file.path,
        title: 'Removed',
        artist: '',
      );
      for (final runtime in runtimes) {
        await (await runtime.initialize()).setQueueAndPlay([
          removed,
          removed,
          _track,
        ]);
      }
      expect(await deleteFile(file.path, deletionEvents: events), isTrue);
      for (final runtime in runtimes) {
        expect(runtime.handler!.queue.value.map((item) => item.id), ['one']);
        expect(runtime.handler!.mediaItem.value?.id, 'one');
        expect(runtime.handler!.playbackState.value.queueIndex, 0);
      }
    },
  );

  test(
    'SAF deletion releases cached playback copies before returning',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cached-deletion-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final cached = await File(
        '${directory.path}/copy.flac',
      ).writeAsString('audio');
      const channel = MethodChannel('com.amwolfstein.sistrum/backend');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => switch (call.method) {
          'safCopyToTemp' => cached.path,
          'safDelete' => true,
          _ => null,
        },
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final events = SourceDeletionEvents();
      final runtime = _runtime(sourceDeletionEvents: events);
      final handler = await runtime.initialize();
      const source = 'content://test.provider/document/song.flac';
      const removed = PlayableMedia(
        id: 'removed',
        source: source,
        title: 'Removed',
        artist: '',
        artUri: 'https://example.com/cover.jpg',
      );
      await handler.setQueueAndPlay([removed, _track]);
      expect(await cached.exists(), isTrue);
      expect(await deleteFile(source, deletionEvents: events), isTrue);
      expect(await cached.exists(), isFalse);
      expect(handler.queue.value.map((item) => item.id), ['one']);
      expect(handler.mediaItem.value?.id, 'one');
    },
  );
}
