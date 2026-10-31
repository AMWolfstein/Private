part of 'music_player_automix_test.dart';

void _registerMusicPlayerAutomix5() {
  test(
    'notification shuffle toggles queue order without restarting audio',
    () async {
      configurePlaybackNotification(
        presentation: const PlaybackNotification(sistrum: true),
        toggleFavorite: (_) async => false,
      );
      await handler.setQueueAndPlay(_tracks, initialIndex: 1);
      final resumed = List.of(_native.resumedSources);

      await handler.customAction(PlaybackNotification.shuffleAction);
      expect(
        handler.playbackState.value.shuffleMode,
        AudioServiceShuffleMode.all,
      );
      expect(handler.queue.value.first.id, 'two');
      expect(handler.queue.value.map((item) => item.id).toSet(), {
        'one',
        'two',
        'three',
      });
      expect(handler.mediaItem.value?.id, 'two');
      expect(
        handler.playbackState.value.controls.last.androidIcon,
        endsWith('shuffle_on'),
      );
      expect(handler.playbackState.value.controls.last.label, 'Shuffle on');

      await handler.customAction(PlaybackNotification.shuffleAction);
      expect(
        handler.playbackState.value.shuffleMode,
        AudioServiceShuffleMode.none,
      );
      expect(handler.queue.value.map((item) => item.id), [
        'one',
        'two',
        'three',
      ]);
      expect(handler.mediaItem.value?.id, 'two');
      expect(
        handler.playbackState.value.controls.last.androidIcon,
        endsWith('shuffle'),
      );
      expect(handler.playbackState.value.controls.last.label, 'Shuffle off');
      expect(handler.playbackState.value.playing, isTrue);
      expect(_native.resumedSources, resumed);
    },
  );

  test(
    'shuffle plays the published queue and off restores the original order',
    () async {
      final tracks = [
        for (var i = 0; i < 8; i++)
          PlayableMedia(
            id: '$i',
            source: '/$i.flac',
            title: '$i',
            artist: 'Artist',
          ),
      ];
      await handler.setQueueAndPlay(tracks, initialIndex: 3);
      await handler.setShuffleMode(AudioServiceShuffleMode.all);
      final planned = handler.queue.value.map((item) => item.id).toList();
      expect(planned.first, '3');
      expect(planned.toSet(), tracks.map((item) => item.id).toSet());
      for (var i = 1; i < planned.length; i++) {
        await handler.skipToNext();
        expect(handler.mediaItem.value?.id, planned[i]);
        expect(_native.sources['music-player'], '/${planned[i]}.flac');
        expect(handler.queue.value.map((item) => item.id), planned);
      }
      final last = handler.mediaItem.value;
      final resumes = _native.resumedSources.length;
      await handler.setShuffleMode(AudioServiceShuffleMode.none);
      expect(
        handler.queue.value.map((item) => item.id),
        tracks.map((item) => item.id),
      );
      expect(handler.mediaItem.value, last);
      expect(handler.playbackState.value.queueIndex, int.parse(planned.last));
      expect(_native.resumedSources.length, resumes);
      await handler.setShuffleMode(AudioServiceShuffleMode.all);
      expect(handler.queue.value.first.id, planned.last);
      expect(handler.mediaItem.value, last);
    },
  );

  test(
    'automatic completion follows shuffle order and respects repeat off',
    () async {
      await handler.setQueueAndPlay(_tracks);
      await handler.setShuffleMode(AudioServiceShuffleMode.all);
      final planned = handler.queue.value.map((item) => item.id).toList();
      for (var i = 1; i < planned.length; i++) {
        await _native.event('music-player', 'audio.onComplete');
        await _until(
          () =>
              handler.mediaItem.value?.id == planned[i] &&
              handler.playbackState.value.processingState ==
                  AudioProcessingState.ready,
        );
      }
      await _native.event('music-player', 'audio.onComplete');
      await _until(
        () =>
            handler.playbackState.value.processingState ==
            AudioProcessingState.completed,
      );
      expect(handler.mediaItem.value?.id, planned.last);
      expect(handler.queue.value.map((item) => item.id), planned);
    },
  );

  test(
    'shuffle restoration retains duplicate entries and explicit queue edits',
    () async {
      await handler.setQueueAndPlay([
        _tracks[0],
        _tracks[0],
        _tracks[1],
        _tracks[2],
      ]);
      await handler.setShuffleMode(AudioServiceShuffleMode.all);
      await handler.enqueue(
        const PlayableMedia(
          id: 'next',
          source: '/next.flac',
          title: 'Next',
          artist: '',
        ),
        playNext: true,
      );
      await handler.enqueueAll([
        const PlayableMedia(
          id: 'last',
          source: '/last.flac',
          title: 'Last',
          artist: '',
        ),
      ]);
      expect(handler.queue.value[1].id, 'next');
      await handler.onSourceDeleted('/two.flac');
      await handler.setShuffleMode(AudioServiceShuffleMode.none);
      expect(handler.queue.value.map((item) => item.id), [
        'one',
        'next',
        'one',
        'three',
        'last',
      ]);
      expect(handler.playbackState.value.queueIndex, 0);
    },
  );

  test(
    'queue removal preserves duplicates, current audio and unshuffled order',
    () async {
      await handler.setQueueAndPlay([
        _tracks[0],
        _tracks[0],
        _tracks[1],
        _tracks[2],
      ]);
      final original = List.of(handler.queue.value);
      await handler.setShuffleMode(AudioServiceShuffleMode.all);
      handler.removeQueuedItem(original[1]);
      handler.removeQueuedItem(original[1]); // A stale swipe is harmless.
      handler.removeQueuedItem(
        original[0],
      ); // The playing occurrence is protected.
      await handler.setShuffleMode(AudioServiceShuffleMode.none);
      expect(handler.queue.value.map((item) => item.id), [
        'one',
        'two',
        'three',
      ]);
      expect(_native.resumedSources, ['/one.flac']);
      await handler.skipToNext();
      handler.removeQueuedItem(original[0]);
      expect(handler.playbackState.value.queueIndex, 0);
      expect(handler.mediaItem.value?.id, 'two');
      expect(_native.sources['music-player'], '/two.flac');
    },
  );

  test(
    'removing an earlier row during preparation preserves duration probing',
    () async {
      _native.emitsDuration = false;
      final gate = Completer<void>();
      _native.sourceGates['/three.flac'] = gate;
      final loading = handler.setQueueAndPlay(_tracks, initialIndex: 2);
      await _until(
        () => _native.calls.any((call) => call.$2 == 'setSourceUrl'),
      );
      handler.removeQueuedItem(handler.queue.value.first);
      gate.complete();
      await loading;
      await _until(
        () => handler.mediaItem.value?.duration == const Duration(seconds: 60),
      );
      expect(handler.playbackState.value.queueIndex, 1);
      expect(handler.mediaItem.value?.id, 'three');
      expect(_native.resumedSources, ['/three.flac']);
    },
  );

  test('restored shuffle can return to the saved original order', () async {
    await handler.restoreSession(
      items: [_tracks[1], _tracks[2], _tracks[0]],
      index: 1,
      position: const Duration(seconds: 12),
      shuffle: true,
      originalOrder: [1, 2, 0],
    );
    await handler.setShuffleMode(AudioServiceShuffleMode.none);
    expect(handler.queue.value.map((item) => item.id), ['one', 'two', 'three']);
    expect(handler.mediaItem.value?.id, 'three');
    expect(handler.playbackState.value.queueIndex, 2);
    expect(handler.playbackState.value.position.inSeconds, 12);
    expect(_native.resumedSources, isEmpty);
  });

  test(
    'notification favorite retains clicked track and ignores double taps',
    () async {
      final save = Completer<void>();
      final selected = <String>[];
      configurePlaybackNotification(
        presentation: const PlaybackNotification(sistrum: true),
        toggleFavorite: (item) async {
          selected.add(item.id);
          await save.future;
          return true;
        },
      );
      handler.mediaItem.add(_tracks.first.toMediaItem());
      final first = handler.customAction(PlaybackNotification.favoriteAction);
      handler.mediaItem.add(_tracks.last.toMediaItem());
      await handler.customAction(PlaybackNotification.favoriteAction);
      expect(selected, ['one']);
      save.complete();
      await first;
      expect(
        handler.playbackState.value.controls.first.androidIcon,
        endsWith('ic_notification_heart'),
        reason:
            'Completing a favorite for the old track must not star the next one',
      );
      await handler.customAction(PlaybackNotification.favoriteAction);
      expect(selected, ['one', 'three']);
      expect(
        handler.playbackState.value.controls.first.androidIcon,
        endsWith('ic_notification_heart_filled'),
      );
    },
  );

  test('notification favorite refreshes without a UI rebuild', () async {
    var loved = false;
    configurePlaybackNotification(
      presentation: const PlaybackNotification(
        sistrum: true,
        favoriteLabel: 'Add to Loved',
        unfavoriteLabel: 'Remove from Loved',
      ),
      toggleFavorite: (_) async => loved = !loved,
    );
    await handler.restoreSession(
      items: _tracks,
      index: 0,
      position: const Duration(seconds: 12),
      shuffle: false,
    );
    await handler.customAction(PlaybackNotification.favoriteAction);
    expect(
      handler.playbackState.value.controls.first.androidIcon,
      endsWith('ic_notification_heart_filled'),
    );
    expect(
      handler.playbackState.value.controls.first.label,
      'Remove from Loved',
    );
    expect(
      handler.playbackState.value.updatePosition,
      const Duration(seconds: 12),
    );

    await handler.customAction(PlaybackNotification.favoriteAction);
    expect(
      handler.playbackState.value.controls.first.androidIcon,
      endsWith('ic_notification_heart'),
    );
    expect(handler.playbackState.value.controls.first.label, 'Add to Loved');
    expect(_native.resumedSources, isEmpty);
  });

  test('failed favorite save leaves the notification icon unchanged', () async {
    configurePlaybackNotification(
      presentation: const PlaybackNotification(sistrum: true),
      toggleFavorite: (_) async => throw StateError('Save failed'),
    );
    handler.mediaItem.add(_tracks.first.toMediaItem());
    await handler.customAction(PlaybackNotification.favoriteAction);
    expect(
      handler.playbackState.value.controls.first.androidIcon,
      endsWith('ic_notification_heart'),
    );
  });

  test(
    'haptics survives an AutoMix handoff followed by a manual skip',
    () async {
      musicPlayerRuntime.configure(
        musicPlayerRuntime.settings.copyWith(musicHaptics: true),
      );
      await _startMix();
      await _until(() => hapticSongs.contains('two'));
      await handler.skipToNext();
      await _until(() => hapticSongs.contains('three'));
      expect(
        _hapticsAnalyzer.paths,
        containsAllInOrder(['/one.flac', '/two.flac', '/three.flac']),
      );
    },
  );

  test('Previous after AutoMix handoff reloads the preceding audio', () async {
    final active = await _startMix();
    await handler.seek(Duration.zero);
    await handler.skipToPrevious();
    expect(handler.mediaItem.value?.id, 'one');
    expect(_native.preparedContents[active], '/one.flac');
    expect(_native.resumedSources.last, '/one.flac');
    expect(_native.playing, {active});
  });

  test(
    'AutoMix prepares and plays the next entry in the shuffled queue',
    () async {
      await handler.setShuffleMode(AudioServiceShuffleMode.all);
      await _prepare();
      final planned = handler.queue.value.map((item) => item.id).toList();
      final incoming = _native.prepared;
      expect(_native.sources[incoming], '/${planned[1]}.flac');
      _native.positions['music-player'] = 55000;
      await _until(() => handler.mediaItem.value?.id == planned[1]);
      expect(handler.queue.value.map((item) => item.id), planned);
      expect(handler.playbackState.value.queueIndex, 1);
    },
  );

  test(
    'disabled AutoMix uses only the ordinary player and no analysis',
    () async {
      await handler.setQueueAndPlay(_tracks);
      _native.positions['music-player'] = 56000;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(_analyzer.calls, isEmpty);
      expect(_native.live, {'music-player'});
      expect(handler.mediaItem.value?.id, 'one');
    },
  );

  test(
    'handoff publishes _native duration and ignores outgoing completion',
    () async {
      final incoming = await _startMix();
      expect(_native.playing, {'music-player', incoming});
      expect(handler.mediaItem.value?.duration, const Duration(minutes: 1));
      expect(handler.playbackState.value.queueIndex, 1);
      await _native.event('music-player', 'audio.onComplete');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(handler.mediaItem.value?.id, 'two');
      expect(handler.playbackState.value.playing, isTrue);
    },
  );
}
