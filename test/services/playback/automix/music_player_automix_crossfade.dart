part of 'music_player_automix_test.dart';

void _registerMusicPlayerAutomixCrossfade() {
  test(
    'pause during overlap stops both decks and restores incoming gain',
    () async {
      final incoming = await _startMix();
      expect(autoMixStatus.value, AutoMixStatus.crossfading);
      await handler.pause();
      expect(_native.live, {incoming});
      expect(_native.playing, isEmpty);
      expect(_native.lastVolume(incoming), 1);
      expect(handler.playbackState.value.playing, isFalse);
    },
  );

  test(
    'matched transition releases outgoing and restores tempo after the fade',
    () async {
      _analyzer.matchBeats = true;
      final incoming = await _startMix(startPosition: 55670);
      expect(autoMixStatus.value, AutoMixStatus.mixing);
      expect(handler.playbackState.value.speed, closeTo(120 / 124, 0.0001));
      await Future<void>.delayed(const Duration(milliseconds: 4200));
      expect(autoMixStatus.value, AutoMixStatus.idle);
      expect(_native.live, {incoming});
      expect(_native.lastVolume(incoming), closeTo(1, 0.0001));
      await Future<void>.delayed(const Duration(seconds: 8));
      expect(handler.playbackState.value.speed, 1);
      expect(_native.playing, {incoming});
      expect(
        _native.calls.where(
          (call) => call.$1 == 'music-player' && call.$2 == 'dispose',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'matched transition starts the incoming song on the outgoing beat',
    () async {
      _analyzer.matchBeats = true;
      await _prepare();
      final incoming = _native.prepared;
      int position(String id) => _native.currentPosition(id);
      // The current song keeps playing while the next decoder starts late.
      final startup = Completer<void>();
      _native.resumeGates[incoming] = startup;
      _native.positions['music-player'] = 55500;
      _native.clocks['music-player'] = Stopwatch()..start();
      await _until(
        () => _native.calls.any(
          (call) => call.$1 == incoming && call.$2 == 'resume',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      startup.complete();
      await _until(() => handler.mediaItem.value?.id == 'two');
      // The first incoming beat (0.17 s) belongs on the outgoing beat at
      // 55.67 s, with the next song slowed from 124 to 120 BPM.
      final expected = 170 + (position('music-player') - 55670) * 120 / 124;
      expect(position(incoming), closeTo(expected, 20));
    },
  );

  test('unverified beat alignment uses an unstretched crossfade', () async {
    _analyzer.matchBeats = true;
    await _prepare();
    final incoming = _native.prepared;
    _native.ignoredSeeks.add(incoming);
    final startup = Completer<void>();
    _native.resumeGates[incoming] = startup;
    _native.positions['music-player'] = 55500;
    _native.clocks['music-player'] = Stopwatch()..start();
    await _until(
      () => _native.calls.any(
        (call) => call.$1 == incoming && call.$2 == 'resume',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    startup.complete();
    await _until(() => handler.mediaItem.value?.id == 'two');
    expect(autoMixStatus.value, AutoMixStatus.crossfading);
    expect(handler.playbackState.value.speed, 1);
    expect(_native.rates[incoming], 1);
  });

  test(
    'phase drift is corrected while mixing and pause restores the rate',
    () async {
      _analyzer.matchBeats = true;
      await _prepare();
      final incoming = _native.prepared;
      _native.positions['music-player'] = 55500;
      _native.clocks['music-player'] = Stopwatch()..start();
      await _until(() => handler.mediaItem.value?.id == 'two');
      expect(autoMixStatus.value, AutoMixStatus.mixing);
      _native.positions[incoming] = _native.positions[incoming]! - 35;
      await _until(() => _native.rates[incoming]! > 120 / 124 + 0.005);
      expect(_native.rates[incoming], lessThanOrEqualTo(120 / 124 * 1.02));
      await handler.pause();
      expect(_native.rates[incoming], 1);
      expect(_native.live, {incoming});
      expect(_native.playing, isEmpty);
    },
  );

  test(
    'a corrected mix finishes at normal speed and releases the outgoing deck',
    () async {
      _analyzer.matchBeats = true;
      await _prepare();
      final incoming = _native.prepared;
      _native.positions['music-player'] = 55500;
      _native.clocks['music-player'] = Stopwatch()..start();
      await _until(() => handler.mediaItem.value?.id == 'two');
      _native.positions[incoming] = _native.positions[incoming]! - 35;
      await _until(() => _native.rates[incoming]! > 120 / 124 + 0.005);
      await Future<void>.delayed(const Duration(seconds: 14));
      expect(handler.mediaItem.value?.id, 'two');
      expect(autoMixStatus.value, AutoMixStatus.idle);
      expect(_native.rates[incoming], 1);
      expect(_native.lastVolume(incoming), 1);
      expect(_native.live, isNot(contains('music-player')));
      expect(_native.playing, {incoming});
    },
  );

  test(
    'missing phase readings keep both decks audible without further corrections',
    () async {
      _analyzer.matchBeats = true;
      await _prepare();
      final incoming = _native.prepared;
      _native.positions['music-player'] = 55500;
      _native.clocks['music-player'] = Stopwatch()..start();
      await _until(() => handler.mediaItem.value?.id == 'two');
      expect(autoMixStatus.value, AutoMixStatus.mixing);
      _native.missingPositions.add('music-player');
      await _until(() => autoMixStatus.value == AutoMixStatus.crossfading);
      expect(_native.playing, {'music-player', incoming});
      expect(_native.lastVolume('music-player'), greaterThan(0));
      expect(_native.lastVolume(incoming), greaterThan(0));
      expect(_native.rates[incoming], closeTo(120 / 124, 0.00001));
      await handler.pause();
      expect(_native.rates[incoming], 1);
      expect(_native.live, {incoming});
    },
  );

  test(
    'uncertain measured beats execute a bass handoff at unchanged tempo',
    () async {
      _analyzer.matchBeats = true;
      _analyzer.confidence = 0.4;
      await _prepare();
      await _until(
        () => _native.sources.values.any((path) => path.endsWith('/tail.wav')),
      );
      expect(_effectRenderer.bassHandoffs, [true]);
      final incoming = _native.sources.entries
          .singleWhere((entry) => entry.value == '/two.flac')
          .key;
      _native.positions['music-player'] = 55000;
      await _until(() => handler.mediaItem.value?.id == 'two');
      expect(autoMixStatus.value, AutoMixStatus.crossfading);
      expect(_native.rates[incoming], 1);
      await handler.pause();
      expect(_native.live, {incoming});
      expect(await _effectRenderer.tails.single.directory.exists(), isFalse);
    },
  );

  test(
    'Auto waits for advancing audio before fading the current song',
    () async {
      _analyzer.matchBeats = true;
      await _prepare();
      final incoming = _native.prepared;
      _native.stalled.add(incoming);
      _native.positions['music-player'] = 55670;
      await _until(() => _native.playing.contains(incoming));
      await Future<void>.delayed(const Duration(milliseconds: 240));
      expect(_native.lastVolume('music-player'), 1);
      expect(_native.lastVolume(incoming), 0);
      expect(handler.mediaItem.value?.id, 'one');

      _native.positions['music-player'] = 58500;
      _native.stalled.remove(incoming);
      _native.clocks[incoming]!.reset();
      await _until(() => handler.mediaItem.value?.id == 'two');
      // Startup consumed most of the outro. Finish the fade within the remaining
      // 1.5 seconds instead of fading against a song that has already ended.
      await _until(() => !_native.live.contains('music-player'));
      expect(_native.lastVolume(incoming), closeTo(1, 0.0001));
    },
  );

  test('a stalled Auto standby leaves the current song playing', () async {
    _analyzer.matchBeats = true;
    await _prepare();
    final incoming = _native.prepared;
    _native.stalled.add(incoming);
    _native.positions['music-player'] = 55670;
    await _until(() => _native.playing.contains(incoming));
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    expect(_native.live, {'music-player'});
    expect(_native.playing, {'music-player'});
    expect(_native.lastVolume('music-player'), 1);
    expect(handler.mediaItem.value?.id, 'one');
    expect(_analyzer.calls, hasLength(2));
  });

  test('a late Auto timer still overlaps within the remaining outro', () async {
    _analyzer.matchBeats = true;
    final incoming = await _startMix(startPosition: 58500);
    await _until(() => !_native.live.contains('music-player'));
    expect(_native.lastVolume(incoming), closeTo(1, 0.0001));
    expect(_native.playing, {incoming});
  });

  test(
    'pausing while Auto waits for audio cancels the pending handoff',
    () async {
      _analyzer.matchBeats = true;
      await _prepare();
      final incoming = _native.prepared;
      _native.stalled.add(incoming);
      _native.positions['music-player'] = 55670;
      await _until(() => _native.playing.contains(incoming));
      await handler.pause();
      _native.stalled.remove(incoming);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(handler.mediaItem.value?.id, 'one');
      expect(handler.playbackState.value.playing, isFalse);
      expect(_native.live, {'music-player'});
      expect(_native.playing, isEmpty);
      expect(_native.lastVolume('music-player'), 1);
    },
  );

  test(
    'seek during overlap cancels fade and seeks only the active deck',
    () async {
      final incoming = await _startMix();
      await handler.seek(const Duration(seconds: 12));
      expect(_native.live, {incoming});
      expect(_native.positions[incoming], 12000);
      expect(_native.lastVolume(incoming), 1);
    },
  );

  test(
    'rendered effect replaces outgoing deck and pause removes its temporary tail',
    () async {
      setAutoMixOptions(const AutoMixOptions(effect: AutoMixEffect.echo));
      await _prepare();
      await _until(() => _native.live.length == 3);
      final incoming = _native.sources.entries
          .singleWhere((entry) => entry.value == '/two.flac')
          .key;
      final effect = _native.sources.entries
          .singleWhere((entry) => entry.value.endsWith('/tail.wav'))
          .key;
      _native.positions['music-player'] = 55000;
      await _until(() => handler.mediaItem.value?.id == 'two');
      await _until(() => !_native.live.contains('music-player'));
      expect(_native.playing, {incoming, effect});
      expect(autoMixStatus.value, AutoMixStatus.crossfading);
      await handler.pause();
      expect(_native.live, {incoming});
      expect(await _effectRenderer.tails.single.directory.exists(), isFalse);
    },
  );

  test('an effect deck that never sounds falls back without a drop', () async {
    setAutoMixOptions(const AutoMixOptions(effect: AutoMixEffect.echo));
    await _prepare();
    await _until(
      () => _native.sources.values.any((path) => path.endsWith('/tail.wav')),
    );
    final effect = _native.sources.entries
        .singleWhere((entry) => entry.value.endsWith('/tail.wav'))
        .key;
    _native.stalled.add(effect);
    _native.positions['music-player'] = 55000;
    await _until(
      () =>
          _native.calls.any((call) => call.$1 == effect && call.$2 == 'resume'),
    );
    // The live song keeps full gain while the silent effect deck is checked.
    expect(_native.lastVolume('music-player'), 1);
    // Allow the production two-second progress deadline to expire.
    await handler.mediaItem
        .firstWhere((item) => item?.id == 'two')
        .timeout(const Duration(seconds: 4));
    expect(_native.live, isNot(contains(effect)));
    expect(_native.lastVolume(effect), anyOf(isNull, 0));
    expect(_native.playing, contains('music-player'));
  });

  test('effect rendering failure retains ordinary crossfade', () async {
    _effectRenderer.fail = true;
    setAutoMixOptions(
      const AutoMixOptions(effect: AutoMixEffect.pitch, pitchSemitones: 2),
    );
    final incoming = await _startMix();
    expect(_native.playing, {'music-player', incoming});
    expect(_effectRenderer.tails, isEmpty);
  });

  test(
    'effect startup keeps dry audio audible and blends before disposal',
    () async {
      setAutoMixOptions(const AutoMixOptions(effect: AutoMixEffect.muffled));
      await _prepare();
      await _until(
        () => _native.sources.values.any((path) => path.endsWith('/tail.wav')),
      );
      final effect = _native.sources.entries
          .singleWhere((entry) => entry.value.endsWith('/tail.wav'))
          .key;
      final ready = Completer<void>();
      _native.resumeGates[effect] = ready;
      _native.positions['music-player'] = 55000;
      await _until(
        () => _native.calls.any(
          (call) => call.$1 == effect && call.$2 == 'resume',
        ),
      );
      expect(_native.lastVolume('music-player'), 1);
      expect(_native.lastVolume(effect), 0);
      expect(_native.playing, contains('music-player'));
      ready.complete();
      await _until(() => (_native.lastVolume(effect) ?? 0) > 0);
      expect(_native.lastVolume('music-player'), inExclusiveRange(0, 1));
      expect(_native.lastVolume(effect), inExclusiveRange(0, 1));
      // Pausing during the handover must clean up both the dry and wet decks.
      await handler.pause();
      expect(_native.live, hasLength(1));
      expect(_native.playing, isEmpty);
      expect(await _effectRenderer.tails.single.directory.exists(), isFalse);
    },
  );

  test(
    'turning AutoMix off releases the standby player without changing song',
    () async {
      await _prepare();
      setAutoMixEnabled(false);
      await _until(() => _native.live.length == 1);
      expect(_native.live, {'music-player'});
      expect(handler.mediaItem.value?.id, 'one');
      expect(_native.playing, {'music-player'});
    },
  );

  test('queue edit never starts the previously prepared next song', () async {
    await _prepare();
    await handler.enqueue(_tracks[2], playNext: true);
    _native.positions['music-player'] = 55000;
    await _until(() => _analyzer.calls.length >= 4);
    await _until(() => handler.mediaItem.value?.id == 'three');
    expect(handler.mediaItem.value?.id, 'three');
  });

  test('manual skip invalidates an analysis still in flight', () async {
    _analyzer.pending = Completer<AutoMixBeatGrid?>();
    setAutoMixEnabled(true);
    await handler.setQueueAndPlay(_tracks);
    await _until(() => _analyzer.calls.isNotEmpty);
    await handler.skipToNext();
    await handler.pause();
    _analyzer.pending!.complete(null);
    _analyzer.pending = null;
    await _until(() => _native.live.length == 1);
    expect(handler.mediaItem.value?.id, 'two');
    expect(_native.playing, isEmpty);
  });
}
