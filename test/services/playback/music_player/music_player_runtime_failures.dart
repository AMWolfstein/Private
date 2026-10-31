part of 'music_player_runtime_test.dart';

void _registerMusicPlayerRuntimeFailures() {
  test('failed player stop cannot undo a confirmed storage deletion', () async {
    final directory = await Directory.systemTemp.createTemp('failed-reaction-');
    addTearDown(() => directory.delete(recursive: true));
    final file = await File(
      '${directory.path}/song.flac',
    ).writeAsString('audio');
    final events = SourceDeletionEvents();
    final decks = <_Deck>[];
    final runtime = _runtime(decks: decks, sourceDeletionEvents: events);
    final handler = await runtime.initialize();
    await handler.setQueueAndPlay([
      PlayableMedia(
        id: 'removed',
        source: file.path,
        title: 'Removed',
        artist: '',
      ),
    ]);
    decks.single.failStop = true;
    expect(await deleteFile(file.path, deletionEvents: events), isTrue);
    expect(await file.exists(), isFalse);
    expect(handler.queue.value, isEmpty);
  });

  test(
    'deletion retires a pending SAF copy without blocking a later copy',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pending-deletion-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final stale = await File(
        '${directory.path}/stale.flac',
      ).writeAsString('old');
      final replacement = await File(
        '${directory.path}/new.flac',
      ).writeAsString('new');
      final copying = Completer<void>();
      final release = Completer<String>();
      const channel = MethodChannel('com.amwolfstein.sistrum/backend');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var copies = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'safDelete') return true;
        if (call.method != 'safCopyToTemp') return null;
        if (++copies > 1) return replacement.path;
        copying.complete();
        return release.future;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final events = SourceDeletionEvents();
      final handler = await _runtime(sourceDeletionEvents: events).initialize();
      const source = 'content://test.provider/document/pending.flac';
      const removed = PlayableMedia(
        id: 'removed',
        source: source,
        title: 'Removed',
        artist: '',
        artUri: 'https://example.com/cover.jpg',
      );
      final playing = handler.setQueueAndPlay([removed]);
      await copying.future;
      try {
        expect(
          await deleteFile(
            source,
            deletionEvents: events,
          ).timeout(const Duration(seconds: 1)),
          isTrue,
        );
        expect(handler.queue.value, isEmpty);
      } finally {
        release.complete(stale.path);
      }
      final restarted = handler.setQueueAndPlay([removed]);
      await playing;
      await restarted;
      expect(copies, 2);
      expect(await stale.exists(), isFalse);
      expect(await replacement.exists(), isTrue);
      expect(handler.mediaItem.value?.id, 'removed');
      expect(handler.playbackState.value.playing, isTrue);
    },
  );

  test(
    'player metadata follows playback after restoring the last session',
    () async {
      final runtime = _runtime();
      final container = ProviderContainer(
        overrides: [musicPlayerRuntimeProvider.overrideWithValue(runtime)],
      );
      addTearDown(container.dispose);
      final titles = <String?>[];
      final subscription = container.listen(currentMediaItemProvider, (
        _,
        next,
      ) {
        if (next.hasValue) titles.add(next.value?.title);
      });
      addTearDown(subscription.close);
      await container.read(currentMediaItemProvider.future);
      final handler = await runtime.initialize();
      const second = PlayableMedia(
        id: 'two',
        source: '/two.flac',
        title: 'Two',
        artist: 'Other',
        duration: Duration(seconds: 60),
      );
      await handler.restoreSession(
        items: [_track, second],
        index: 0,
        position: const Duration(seconds: 15),
        shuffle: false,
      );
      await container.pump();
      expect(titles.last, 'One');
      final controller = container.read(musicPlayerControllerProvider);
      await controller.next();
      await container.pump();
      expect(handler.playbackState.value.playing, isTrue);
      expect(titles.last, 'Two');

      await controller.playAll([_track]);
      await container.pump();
      expect(handler.playbackState.value.playing, isTrue);
      expect(titles.last, 'One');
      expect(
        container.read(currentMediaItemProvider).value?.extras?['source'],
        _track.source,
      );
    },
  );

  test(
    'pre-init events have empty values and cancellation never waits for init',
    () async {
      var calls = 0;
      final runtime = _runtime(
        initialize: (builder) async {
          calls++;
          return builder();
        },
      );
      final items = <MediaItem?>[];
      final queues = <List<MediaItem>>[];
      final states = <PlaybackState>[];
      final itemEvents = runtime.mediaItemEvents().listen(items.add);
      final queueEvents = runtime.queueEvents().listen(queues.add);
      final stateEvents = runtime.playbackStateEvents().listen(states.add);
      await _settle();

      expect(items, [null]);
      expect(queues, [isEmpty]);
      expect(states, isEmpty);
      await Future.wait([
        itemEvents.cancel(),
        queueEvents.cancel(),
        stateEvents.cancel(),
      ]).timeout(const Duration(seconds: 1));
      expect(calls, 0);
      await runtime.initialize();
      await _settle();
      expect(items, [null]);
      expect(queues, [isEmpty]);
      expect(states, isEmpty);
    },
  );

  test(
    'pending init is deduplicated and uses the latest live configuration',
    () async {
      final ready = Completer<PlaybackHandler>();
      final volume = StreamController<double>.broadcast();
      addTearDown(volume.close);
      var calls = 0;
      late PlaybackHandler created;
      final runtime = _runtime(
        volumeChanges: volume.stream,
        initialize: (builder) {
          calls++;
          created = builder();
          return ready.future;
        },
      );
      final items = <MediaItem?>[];
      final events = runtime.mediaItemEvents().listen(items.add);
      addTearDown(events.cancel);
      runtime.configure(runtime.settings.copyWith(autoMix: true));
      final first = runtime.initialize();
      expect(runtime.initialize(), same(first));
      await _settle();
      expect(calls, 1);
      expect(runtime.handler, isNull);
      expect(volume.hasListener, isFalse);
      runtime.configure(runtime.settings.copyWith(pauseOnMute: true));
      created.mediaItem.add(_item);
      await _settle();
      expect(volume.hasListener, isTrue);
      expect(items, [null]);
      ready.complete(created);
      expect(await first, same(created));
      expect(await runtime.initialize(), same(created));
      await _settle();
      expect(items, [null, _item]);
      expect(calls, 1);
      expect(runtime.settings.autoMix, isTrue);
      await runtime.dispose();
      expect(volume.hasListener, isFalse);
    },
  );

  test('failed initialization releases its handler and can retry', () async {
    var calls = 0;
    final decks = <_Deck>[];
    final runtime = _runtime(
      decks: decks,
      initialize: (builder) async {
        final handler = builder();
        if (++calls == 1) throw StateError('Initialization failed');
        return handler;
      },
    );
    await expectLater(runtime.initialize(), throwsStateError);
    expect(
      LogBuffer().entries.any(
        (entry) =>
            entry.tag == 'MusicPlayerRuntime' &&
            entry.level == 'ERROR' &&
            entry.message == 'Failed to initialize playback' &&
            entry.error?.contains('Initialization failed') == true,
      ),
      isTrue,
    );
    expect(runtime.handler, isNull);
    expect(decks.single.disposals, 1);
    final retried = await runtime.initialize();
    expect(runtime.handler, same(retried));
    expect(calls, 2);
    await runtime.dispose();
    expect(decks.map((deck) => deck.disposals), [1, 1]);
  });

  test(
    'deck construction failure leaves no partial handler and can retry',
    () async {
      var calls = 0;
      final deck = _Deck();
      final runtime = _runtime(
        createDeck: (_) {
          if (++calls == 1) throw StateError('Deck creation failed');
          return deck;
        },
      );
      await expectLater(runtime.initialize(), throwsStateError);
      expect(runtime.handler, isNull);
      final handler = await runtime.initialize();
      expect(runtime.handler, same(handler));
      expect(calls, 2);
      await runtime.dispose();
      expect(deck.disposals, 1);
    },
  );

  test('an initializer returning a disposed handler can retry', () async {
    var calls = 0;
    final runtime = _runtime(
      initialize: (builder) async {
        final handler = builder();
        if (++calls == 1) await handler.dispose();
        return handler;
      },
    );
    await expectLater(runtime.initialize(), throwsStateError);
    final handler = await runtime.initialize();
    expect(runtime.handler, same(handler));
    expect(handler.isDisposed, isFalse);
    expect(calls, 2);
  });

  test(
    'runtime disposal retires a pending handler and closes its events',
    () async {
      final ready = Completer<PlaybackHandler>();
      final decks = <_Deck>[];
      late PlaybackHandler created;
      final runtime = _runtime(
        decks: decks,
        initialize: (builder) {
          created = builder();
          return ready.future;
        },
      );
      final closed = Completer<void>();
      final events = runtime.mediaItemEvents().listen(
        (_) {},
        onDone: closed.complete,
      );
      addTearDown(events.cancel);
      final pending = runtime.initialize();
      final failed = expectLater(pending, throwsStateError);
      await _settle();
      final disposed = runtime.dispose();
      expect(runtime.dispose(), same(disposed));
      expect(created.isDisposed, isTrue);
      expect(runtime.handler, isNull);
      ready.complete(created);
      await failed;
      await disposed;
      await closed.future.timeout(const Duration(seconds: 1));
      expect(decks.single.disposals, 1);
      await expectLater(runtime.initialize(), throwsStateError);
    },
  );

  test(
    'a delayed builder cannot create playback resources after disposal',
    () async {
      final build = Completer<void>();
      final decks = <_Deck>[];
      final runtime = _runtime(
        decks: decks,
        initialize: (builder) async {
          await build.future;
          return builder();
        },
      );
      final failed = expectLater(runtime.initialize(), throwsStateError);
      await _settle();
      final disposed = runtime.dispose();
      build.complete();
      await failed;
      await disposed;
      expect(runtime.handler, isNull);
      expect(decks, isEmpty);
    },
  );

  test(
    'event subscribers follow a replacement and ignore the retired handler',
    () async {
      final runtime = _runtime();
      final items = <MediaItem?>[];
      final queues = <List<MediaItem>>[];
      final itemEvents = runtime.mediaItemEvents().listen(items.add);
      final queueEvents = runtime.queueEvents().listen(queues.add);
      addTearDown(itemEvents.cancel);
      addTearDown(queueEvents.cancel);
      final first = await runtime.initialize();
      first.mediaItem.add(_item);
      first.queue.add([_item]);
      await _settle();
      expect(items.last, _item);
      expect(queues.last, [_item]);
      await first.dispose();
      await _settle();
      expect(items.last, isNull);
      expect(queues.last, isEmpty);
      first.mediaItem.add(const MediaItem(id: 'stale', title: 'Stale'));
      first.queue.add([_item]);
      final second = await runtime.initialize();
      const replacement = MediaItem(id: 'two', title: 'Two');
      second.mediaItem.add(replacement);
      second.queue.add([replacement]);
      await _settle();
      expect(items.last, replacement);
      expect(queues.last, [replacement]);
      expect(items.whereType<MediaItem>().map((item) => item.id), [
        'one',
        'two',
      ]);
    },
  );
}
