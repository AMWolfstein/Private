part of 'music_player_runtime_test.dart';

void _registerMusicPlayerRuntime1() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'sleep timer pause failure is caught and keeps a retryable track',
    () async {
      final deck = _Deck();
      final handler = await _runtime(createDeck: (_) => deck).initialize();
      await handler.setQueueAndPlay([_track]);
      deck.failPause = true;
      final failed = handler.playbackState.firstWhere(
        (state) => state.errorMessage != null,
      );
      handler.setSleepTimer(const Duration(milliseconds: 1));
      final state = await failed.timeout(const Duration(seconds: 5));
      expect(state.playing, isFalse);
      expect(state.errorMessage, contains('Pause failed'));
      expect(handler.mediaItem.value?.id, _track.id);
      deck.failPause = false;
    },
  );

  test(
    'completion transport failure is caught and published as a playback error',
    () async {
      final deck = _CompletionDeck();
      final handler = await _runtime(createDeck: (_) => deck).initialize();
      const second = PlayableMedia(
        id: 'two',
        source: '/two.flac',
        title: 'Two',
        artist: 'Artist',
        duration: Duration(seconds: 60),
      );
      await handler.setQueueAndPlay([_track, second]);
      deck.failStop = true;
      deck.completions.add(null);
      await _settle();
      await _settle();
      expect(handler.playbackState.value.playing, isFalse);
      expect(
        handler.playbackState.value.errorMessage,
        contains('Transport failed'),
      );
      expect(handler.mediaItem.value, isNotNull);
      deck.failStop = false;
    },
  );

  test(
    'last-track completion reports stop failure after pending autoplay appends',
    () async {
      final deck = _CompletionDeck();
      final libraryStarted = Completer<void>();
      final candidates = Completer<List<PlayableMedia>>();
      late final MusicPlayerRuntime runtime;
      runtime = _runtime(
        settings: const AppSettings(
          pauseOnMute: false,
          autoplay: true,
          autoplayPersonalization: false,
        ),
        createDeck: (_) => deck,
        initialize: (_) async => MusicPlayerHandler(
          runtime: runtime,
          autoplayLibraryLoader: (_) {
            if (!libraryStarted.isCompleted) libraryStarted.complete();
            return candidates.future;
          },
        ),
      );
      addTearDown(() {
        if (!candidates.isCompleted) candidates.complete([]);
      });
      final handler = await runtime.initialize();
      await handler.setQueueAndPlay([_track]);
      await libraryStarted.future;
      expect(handler.queue.value.map((item) => item.id), ['one']);
      expect(
        handler.playbackState.value.repeatMode,
        AudioServiceRepeatMode.none,
      );

      // The handler's listener runs first and awaits the already-pending fill.
      // Observing delivery avoids a guessed event-loop delay before release.
      final completionDelivered = deck.completions.stream.first;
      deck.completions.add(null);
      await completionDelivered;
      final failed = handler.playbackState.firstWhere(
        (state) => state.errorMessage != null,
      );
      deck.failStop = true;
      try {
        candidates.complete([
          const PlayableMedia(
            id: 'two',
            source: '/two.flac',
            title: 'Two',
            artist: 'Other Artist',
            duration: Duration(seconds: 60),
          ),
        ]);
        final state = await failed.timeout(const Duration(seconds: 5));
        expect(handler.queue.value.map((item) => item.id), ['one', 'two']);
        expect(state.playing, isFalse);
        expect(state.errorMessage, contains('Transport failed'));
        expect(handler.mediaItem.value?.id, _track.id);
      } finally {
        deck.failStop = false;
      }
    },
  );

  test(
    'seek before restored source load replaces the saved position',
    () async {
      final decks = <_Deck>[];
      final handler = await _runtime(decks: decks).initialize();
      await handler.restoreSession(
        items: [_track],
        index: 0,
        position: const Duration(seconds: 12),
        shuffle: false,
      );
      await handler.seek(const Duration(seconds: 24));
      expect(decks.single.seeks, isEmpty);
      expect(
        handler.playbackState.value.updatePosition,
        const Duration(seconds: 24),
      );
      await handler.play();
      expect(decks.single.seeks.last, const Duration(seconds: 24));
    },
  );

  test('previous restart before restored load is retained on play', () async {
    final decks = <_Deck>[];
    final handler = await _runtime(decks: decks).initialize();
    await handler.restoreSession(
      items: [_track],
      index: 0,
      position: const Duration(seconds: 12),
      shuffle: false,
    );
    await handler.skipToPrevious();
    expect(decks.single.seeks, isEmpty);
    expect(handler.playbackState.value.position, Duration.zero);
    await handler.play();
    expect(decks.single.position, Duration.zero);
  });

  test(
    'seek while preparation cancellation waits becomes the load position',
    () async {
      final deck = _Deck();
      final handler = await _runtime(createDeck: (_) => deck).initialize();
      final cancellation = Completer<void>();
      deck.cancellationBarrier = cancellation;
      addTearDown(() {
        if (!cancellation.isCompleted) cancellation.complete();
      });
      final loading = handler.setQueueAndPlay([_track]);
      await deck.cancellationStarted.future;
      // _playIndex has not enqueued its source load yet. The seek must survive
      // even though its serialized operation finishes before that load begins.
      await handler.seek(const Duration(seconds: 24));
      expect(deck.sourceStarted.isCompleted, isFalse);
      expect(deck.seeks, isEmpty);
      expect(
        handler.playbackState.value.updatePosition,
        const Duration(seconds: 24),
      );
      cancellation.complete();
      await loading;
      expect(deck.seeks.last, const Duration(seconds: 24));
      expect(deck.position, const Duration(seconds: 24));
      expect(
        handler.playbackState.value.updatePosition,
        const Duration(seconds: 24),
      );
    },
  );

  test('seek during source preparation waits for the new source', () async {
    final barrier = Completer<void>();
    final deck = _Deck()..sourceBarrier = barrier;
    final handler = await _runtime(createDeck: (_) => deck).initialize();
    final loading = handler.setQueueAndPlay([_track]);
    await deck.sourceStarted.future;
    final seeking = handler.seek(const Duration(seconds: 24));
    expect(deck.seeks, isEmpty);
    barrier.complete();
    await loading;
    await seeking;
    expect(deck.seeks.last, const Duration(seconds: 24));
    expect(
      handler.playbackState.value.updatePosition,
      const Duration(seconds: 24),
    );
  });

  test(
    'deleting a queued source cannot revive an explicitly stopped session',
    () async {
      final handler = await _runtime().initialize();
      const second = PlayableMedia(
        id: 'two',
        source: '/two.flac',
        title: 'Two',
        artist: 'Artist',
        duration: Duration(seconds: 60),
      );
      await handler.setQueueAndPlay([_track, second]);
      await handler.stop();
      await handler.onSourceDeleted(_track.source);
      expect(handler.queue.value.map((item) => item.id), ['two']);
      expect(handler.mediaItem.value, isNull);
      expect(handler.playbackState.value.queueIndex, isNull);
      expect(handler.playbackState.value.playing, isFalse);
    },
  );

  test('Play after Pause does not join an invalidated resume', () async {
    final deck = _Deck();
    final handler = await _runtime(createDeck: (_) => deck).initialize();
    await handler.setQueueAndPlay([_track]);
    await handler.pause();
    final barrier = Completer<void>();
    deck.resumeBarrier = barrier;
    deck.resumeStarted = Completer<void>();
    final oldPlay = handler.play();
    await deck.resumeStarted.future;
    final pausing = handler.pause();
    final latestPlay = handler.play();
    barrier.complete();
    await Future.wait([oldPlay, pausing, latestPlay]);
    expect(deck.state, PlayerState.playing);
    expect(handler.playbackState.value.playing, isTrue);
  });

  test(
    'trained personalized ranking runs through the real autoplay worker',
    () async {
      final model = AutoplayPreferenceModel();
      const preferred = AutoplayLearningTrack(
        source: '/jazz.flac',
        title: 'Jazz',
        artist: 'Jazz Artist',
        genre: 'Jazz',
        duration: Duration(seconds: 60),
      );
      const avoided = AutoplayLearningTrack(
        source: '/rock.flac',
        title: 'Rock',
        artist: 'Rock Artist',
        genre: 'Rock',
        duration: Duration(seconds: 60),
      );
      const seed = AutoplayLearningTrack(
        source: '/one.flac',
        title: 'One',
        artist: 'Artist',
      );
      for (var i = 0; i < 80; i++) {
        model.learn(preferred, previous: seed, at: DateTime.now(), reward: 1);
        model.learn(avoided, previous: seed, at: DateTime.now(), reward: 0);
      }
      final learning = AutoplayPersonalization(
        load: () async => model.encode(),
        save: (_) async {},
      );
      final runtime = _runtime(
        settings: const AppSettings(
          pauseOnMute: false,
          autoplay: true,
          autoplayPersonalization: true,
        ),
        createPersonalization: () => learning,
      );
      final handler = MusicPlayerHandler(
        runtime: runtime,
        autoplayLibraryLoader: (_) async => [
          const PlayableMedia(
            id: 'rock',
            source: '/rock.flac',
            title: 'Rock',
            artist: 'Rock Artist',
            genre: 'Rock',
            duration: Duration(seconds: 60),
          ),
          const PlayableMedia(
            id: 'jazz',
            source: '/jazz.flac',
            title: 'Jazz',
            artist: 'Jazz Artist',
            genre: 'Jazz',
            duration: Duration(seconds: 60),
          ),
        ],
      );
      await learning.ensureLoaded();
      await handler.setQueueAndPlay([_track]);
      await handler.queue
          .firstWhere((queue) => queue.length == 3)
          .timeout(const Duration(seconds: 5));
      expect(handler.queue.value.map((item) => item.id), [
        'one',
        'jazz',
        'rock',
      ]);
      expect(handler.playbackState.value.playing, isTrue);
      await resetAutoplayLearning(runtime: runtime);
      expect(learning.observations, 0);
      await handler.queue
          .firstWhere((queue) => queue.length == 3)
          .timeout(const Duration(seconds: 5));
      expect(handler.queue.value.first.id, 'one');
      runtime.configure(
        runtime.settings.copyWith(autoplayPersonalization: false),
      );
      await handler.queue
          .firstWhere((queue) => queue.length == 3)
          .timeout(const Duration(seconds: 5));
      expect(handler.queue.value.first.id, 'one');
      expect(handler.playbackState.value.playing, isTrue);
    },
  );
}
