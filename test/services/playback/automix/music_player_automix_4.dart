part of 'music_player_automix_test.dart';

void _registerMusicPlayerAutomix4() {
  test(
    'Autoplay fills a single-track queue and follows its visible order',
    () async {
      setAutoplayEnabled(true);
      await handler.setQueueAndPlay([_tracks.first]);
      await _until(() => handler.queue.value.length == 3);
      final planned = handler.queue.value.toList();
      expect(planned.first.id, 'one');
      expect(
        planned.skip(1).every((item) => item.extras?['autoplay'] == true),
        isTrue,
      );
      await _native.event('music-player', 'audio.onComplete');
      await _until(() => handler.mediaItem.value?.id == planned[1].id);
      expect(_native.sources['music-player'], planned[1].extras?['source']);
      setAutoplayEnabled(false);
      expect(handler.queue.value.map((item) => item.id), [
        'one',
        planned[1].id,
      ]);
      expect(handler.playbackState.value.playing, isTrue);
    },
  );

  test(
    'manual additions precede Autoplay and survive disabling or repeat',
    () async {
      setAutoplayEnabled(true);
      await handler.setQueueAndPlay([_tracks.first]);
      await _until(() => handler.queue.value.length == 3);
      const manual = PlayableMedia(
        id: 'manual',
        source: '/manual.flac',
        title: 'Manual',
        artist: 'Other',
      );
      await handler.enqueue(manual);
      expect(handler.queue.value[1].id, 'manual');
      await handler.setShuffleMode(AudioServiceShuffleMode.all);
      expect(handler.queue.value[1].id, 'manual');
      await handler.setShuffleMode(AudioServiceShuffleMode.none);
      expect(handler.queue.value[1].id, 'manual');
      await handler.setRepeatMode(AudioServiceRepeatMode.all);
      expect(handler.queue.value.map((item) => item.id), ['one', 'manual']);
      await handler.setRepeatMode(AudioServiceRepeatMode.none);
      await _until(() => handler.queue.value.length == 4);
      setAutoplayEnabled(false);
      expect(handler.queue.value.map((item) => item.id), ['one', 'manual']);
    },
  );

  test(
    'pending Autoplay is discarded after disabling or replacing the queue',
    () async {
      final pending = Completer<List<PlayableMedia>>();
      autoplayLoader = (_) => pending.future;
      setAutoplayEnabled(true);
      await handler.setQueueAndPlay([_tracks.first]);
      setAutoplayEnabled(false);
      await handler.setQueueAndPlay([_tracks.last]);
      pending.complete(_tracks);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(handler.queue.value.map((item) => item.id), ['three']);
      expect(_native.sources['music-player'], '/three.flac');
    },
  );

  test('pause during an Autoplay refill prevents automatic resume', () async {
    final pending = Completer<List<PlayableMedia>>();
    autoplayLoader = (_) => pending.future;
    setAutoplayEnabled(true);
    await handler.setQueueAndPlay([_tracks.first]);
    await _native.event('music-player', 'audio.onComplete');
    await handler.pause();
    pending.complete(_tracks);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(handler.mediaItem.value?.id, 'one');
    expect(handler.playbackState.value.playing, isFalse);
    expect(_native.resumedSources, ['/one.flac']);
  });

  test(
    'replacing a queue invalidates an in-flight recommendation batch',
    () async {
      final pending = Completer<List<PlayableMedia>>();
      autoplayLoader = (seed) =>
          seed.id == 'one' ? pending.future : Future.value([]);
      setAutoplayEnabled(true);
      await handler.setQueueAndPlay([_tracks.first]);
      await handler.setQueueAndPlay([_tracks.last]);
      pending.complete(_tracks);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(handler.queue.value.map((item) => item.id), ['three']);
      expect(_native.sources['music-player'], '/three.flac');
    },
  );

  test(
    'duplicate completion while recommendations load advances only once',
    () async {
      final pending = Completer<List<PlayableMedia>>();
      autoplayLoader = (_) => pending.future;
      setAutoplayEnabled(true);
      await handler.setQueueAndPlay([_tracks.first]);
      await _native.event('music-player', 'audio.onComplete');
      await _native.event('music-player', 'audio.onComplete');
      pending.complete(_tracks);
      await _until(() => handler.playbackState.value.queueIndex == 1);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(handler.playbackState.value.queueIndex, 1);
      expect(handler.mediaItem.value?.id, handler.queue.value[1].id);
    },
  );

  test(
    'Autoplay never adds a song dismissed from the current queue again',
    () async {
      setAutoplayEnabled(true);
      await handler.setQueueAndPlay([_tracks.first]);
      await _until(() => handler.queue.value.length == 3);
      final removed = handler.queue.value[1];
      handler.removeQueuedItem(removed);
      await handler.skipToNext();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(handler.queue.value.any((item) => item.id == removed.id), isFalse);
    },
  );

  test('empty Library ends playback and does not repeatedly refill', () async {
    var loads = 0;
    autoplayLoader = (_) async {
      loads++;
      return [];
    };
    setAutoplayEnabled(true);
    await handler.setQueueAndPlay([_tracks.first]);
    await _native.event('music-player', 'audio.onComplete');
    await _until(
      () =>
          handler.playbackState.value.processingState ==
          AudioProcessingState.completed,
    );
    expect(handler.queue.value, hasLength(1));
    expect(loads, 1);
  });

  test(
    'rapid Next keeps the final audible source and displayed title together',
    () async {
      final gate = Completer<void>();
      _native.sourceGates['/one.flac'] = gate;
      final first = handler.setQueueAndPlay(_tracks);
      await _until(() => _native.calls.any((c) => c.$2 == 'setSourceUrl'));
      final second = handler.skipToNext();
      final third = handler.skipToNext();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      gate.complete();
      await Future.wait([first, second, third]);
      expect(handler.mediaItem.value?.id, 'three');
      expect(_native.sources['music-player'], '/three.flac');
      expect(_native.resumedSources, ['/three.flac']);
    },
  );

  for (final shuffle in [false, true]) {
    test('Previous changes both title and audio (shuffle: $shuffle)', () async {
      if (shuffle) await handler.setShuffleMode(AudioServiceShuffleMode.all);
      await handler.setQueueAndPlay(_tracks);
      final ordered = handler.queue.value.map((item) => item.id).toList();
      await handler.skipToNext();
      await handler.skipToNext();
      expect(_native.sources['music-player'], '/${ordered[2]}.flac');

      // Repeat-one affects automatic completion, not an explicit Previous.
      await handler.setRepeatMode(AudioServiceRepeatMode.one);
      for (final id in ordered.take(2).toList().reversed) {
        await handler.skipToPrevious();
        expect(handler.mediaItem.value?.id, id);
        expect(_native.preparedContents['music-player'], '/$id.flac');
        expect(_native.resumedSources.last, '/$id.flac');
        expect(_native.playing, {'music-player'});
      }
    });
  }

  test('rapid Previous discards a later track still preparing', () async {
    final gate = Completer<void>();
    _native.sourceGates['/three.flac'] = gate;
    final last = handler.setQueueAndPlay(_tracks, initialIndex: 2);
    await _until(() => _native.calls.any((c) => c.$2 == 'setSourceUrl'));
    final second = handler.skipToPrevious();
    final first = handler.skipToPrevious();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    gate.complete();
    await Future.wait([last, second, first]);
    expect(handler.mediaItem.value?.id, 'one');
    expect(_native.preparedContents['music-player'], '/one.flac');
    expect(_native.resumedSources, ['/one.flac']);
  });

  test('Next and Previous reload a recycled SAF descriptor', () async {
    const descriptor = '/proc/self/fd/42';
    _native.sourceContents[descriptor] = 'first file';
    await handler.setQueueAndPlay([
      const PlayableMedia(
        id: 'first',
        source: descriptor,
        title: 'First',
        artist: 'Artist',
      ),
      const PlayableMedia(
        id: 'second',
        source: descriptor,
        title: 'Second',
        artist: 'Artist',
      ),
    ]);
    expect(_native.preparedContents['music-player'], 'first file');
    _native.sourceContents[descriptor] = 'second file';
    await handler.skipToNext();
    expect(handler.mediaItem.value?.title, 'Second');
    expect(_native.preparedContents['music-player'], 'second file');
    expect(_native.playing, contains('music-player'));

    _native.sourceContents[descriptor] = 'first file';
    await handler.skipToPrevious();
    expect(handler.mediaItem.value?.title, 'First');
    expect(_native.preparedContents['music-player'], 'first file');
    expect(_native.playing, {'music-player'});
  });

  test('replacing a queue during preparation drops the old request', () async {
    final gate = Completer<void>();
    _native.sourceGates['/one.flac'] = gate;
    final first = handler.setQueueAndPlay(_tracks);
    await _until(() => _native.calls.any((c) => c.$2 == 'setSourceUrl'));
    final replacement = handler.setQueueAndPlay([_tracks[1]]);
    gate.complete();
    await Future.wait([first, replacement]);
    expect(handler.mediaItem.value?.id, 'two');
    expect(_native.sources['music-player'], '/two.flac');
    expect(_native.resumedSources, ['/two.flac']);
  });

  for (final stop in [false, true]) {
    test(
      'a pending _prepare cannot resume after ${stop ? 'stop' : 'pause'}',
      () async {
        final gate = Completer<void>();
        _native.sourceGates['/one.flac'] = gate;
        final first = handler.setQueueAndPlay(_tracks);
        await _until(() => _native.calls.any((c) => c.$2 == 'setSourceUrl'));
        final cancel = stop ? handler.stop() : handler.pause();
        gate.complete();
        await Future.wait([first, cancel]);
        expect(_native.resumedSources, isEmpty);
        expect(_native.playing, isEmpty);
        expect(handler.playbackState.value.playing, isFalse);
        if (stop) expect(handler.mediaItem.value, isNull);
      },
    );
  }

  test(
    'Sistrum notification follows theme and keeps transport state',
    () async {
      await handler.restoreSession(
        items: _tracks,
        index: 0,
        position: const Duration(seconds: 12),
        shuffle: false,
      );
      configurePlaybackNotification(
        presentation: const PlaybackNotification(
          sistrum: true,
          mediaId: 'one',
          source: '/one.flac',
          loved: true,
        ),
        toggleFavorite: (_) async => false,
      );
      final state = handler.playbackState.value;
      expect(state.playing, isFalse);
      expect(state.updatePosition, const Duration(seconds: 12));
      expect(state.controls.map((control) => control.action), [
        MediaAction.custom,
        MediaAction.skipToPrevious,
        MediaAction.play,
        MediaAction.skipToNext,
        MediaAction.custom,
      ]);
      expect(state.controls.first.androidIcon, contains('heart_filled'));
      expect(
        state.controls.last.customAction?.name,
        PlaybackNotification.shuffleAction,
      );
      expect(state.androidCompactActionIndices, [1, 2, 3]);

      configurePlaybackNotification(
        presentation: const PlaybackNotification(),
        toggleFavorite: (_) async => false,
      );
      expect(handler.playbackState.value.controls, [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.skipToNext,
      ]);
      expect(handler.playbackState.value.androidCompactActionIndices, [
        0,
        1,
        2,
      ]);
      expect(handler.playbackState.value.updatePosition, state.updatePosition);
      handler.playbackState.add(
        PlaybackState(
          playing: true,
          processingState: AudioProcessingState.ready,
          updatePosition: const Duration(seconds: 12),
          updateTime: DateTime.now().subtract(const Duration(seconds: 5)),
        ),
      );
      configurePlaybackNotification(
        presentation: const PlaybackNotification(sistrum: true),
        toggleFavorite: (_) async => false,
      );
      expect(
        handler.playbackState.value.updatePosition.inMilliseconds,
        inInclusiveRange(17000, 17200),
        reason: 'Changing icons must not reset the live playback position',
      );
    },
  );
}
