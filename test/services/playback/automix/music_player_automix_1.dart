part of 'music_player_automix_test.dart';

late _AudioNative _native;

late _Analyzer _analyzer;

late _EffectRenderer _effectRenderer;

late MusicPlayerHandler handler;

late AutoplayLibraryLoader autoplayLoader;

late _HapticsAnalyzer _hapticsAnalyzer;

late List<String?> hapticSongs;

Future<void> _prepare() async {
  setAutoMixEnabled(true);
  await handler.setQueueAndPlay(_tracks);
  await _until(() => _analyzer.calls.length >= 2);
  await _until(() => _native.calls.any((call) => call.$2 == 'setPlaybackRate'));
}

Future<String> _startMix({int startPosition = 55000}) async {
  await _prepare();
  final incoming = _native.prepared;
  _native.positions['music-player'] = startPosition;
  await _until(() => handler.mediaItem.value?.id == 'two');
  await _until(() => (_native.lastVolume(incoming) ?? 0) > 0);
  return incoming;
}

void _registerMusicPlayerAutomix1() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUp(() {
    musicPlayerRuntime.configure(
      musicPlayerRuntime.settings.copyWith(musicHaptics: false),
    );
    setPlaybackAutomationOptions(
      enabled: true,
      pauseOnMute: false,
      playOnHeadphonesConnected: false,
    );
    setAutoMixEnabled(false);
    setAutoMixOptions(const AutoMixOptions());
    setUsbBitPerfectEnabled(false);
    setAutoplayEnabled(false);
    _native = _AudioNative()..install();
    _analyzer = _Analyzer();
    _effectRenderer = _EffectRenderer();
    autoplayLoader = (_) async => _tracks;
    _hapticsAnalyzer = _HapticsAnalyzer();
    hapticSongs = [];
    handler = MusicPlayerHandler(
      autoMixAnalyzer: _analyzer,
      autoMixEffectRenderer: _effectRenderer,
      autoplayLibraryLoader: (seed) => autoplayLoader(seed),
      hapticsAnalyzer: _hapticsAnalyzer,
      hapticPulse: (_, _) async => hapticSongs.add(handler.mediaItem.value?.id),
    );
  });

  tearDown(() async {
    await handler.dispose();
    configurePlaybackNotification(
      presentation: const PlaybackNotification(),
      toggleFavorite: (_) async => false,
    );
    _analyzer.pending?.complete(null);
    setAutoMixEnabled(false);
    setUsbBitPerfectEnabled(false);
    setAutoplayEnabled(false);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(_native.live, isEmpty);
    expect(_native.playing, isEmpty);
    expect(autoMixStatus.value, AutoMixStatus.idle);
    for (final tail in _effectRenderer.tails) {
      expect(await tail.directory.exists(), isFalse);
    }
  });

  test(
    'USB preference is opt-in and persists with existing DSP preferences',
    () {
      const defaults = AppSettings();
      expect(defaults.usbBitPerfect, isFalse);
      expect(defaults.usbDirect, isFalse);
      expect(defaults.usbDsdOverPcm, isFalse);
      expect(defaults.usbAllowFixedVolume, isFalse);
      expect(defaults.dapExclusive, isFalse);
      final upgraded = AppSettings.fromJson({
        'usbBitPerfect': true,
        'usbDirect': true,
      });
      expect(upgraded.usbAllowFixedVolume, isFalse);
      final selected = defaults.copyWith(
        usbBitPerfect: true,
        usbDirect: true,
        usbDsdOverPcm: true,
        usbAllowFixedVolume: true,
        autoMix: true,
        playbackNormalization: true,
      );
      final restored = AppSettings.fromJson(selected.toJson());
      expect(restored.usbBitPerfect, isTrue);
      expect(restored.usbDirect, isTrue);
      expect(restored.usbDsdOverPcm, isTrue);
      expect(restored.usbAllowFixedVolume, isTrue);
      expect(
        AppSettings.fromJson(
          defaults.copyWith(dapExclusive: true).toJson(),
        ).dapExclusive,
        isTrue,
      );
      expect(restored.autoMix, isTrue);
      expect(restored.playbackNormalization, isTrue);
    },
  );

  test(
    'USB mode prevents a second DSP deck even when AutoMix is enabled',
    () async {
      setAutoMixEnabled(true);
      setUsbBitPerfectEnabled(true);
      await handler.setQueueAndPlay(_tracks);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(_native.live, {'music-player'});
      expect(_native.lastVolume('music-player'), 1);
      expect(_analyzer.calls, isEmpty);
    },
  );

  group('music haptics transport', () {
    void enableHaptics() => musicPlayerRuntime.configure(
      musicPlayerRuntime.settings.copyWith(musicHaptics: true),
    );

    test('direct documents work without AutoMix resolved metadata', () async {
      enableHaptics();
      const source = 'content://music/document/first.flac';
      handler.mediaItem.add(
        const MediaItem(
          id: 'document',
          title: 'Document',
          extras: {'source': source},
        ),
      );
      handler.playbackState.add(
        PlaybackState(
          playing: true,
          processingState: AudioProcessingState.ready,
        ),
      );
      await _until(() => hapticSongs.isNotEmpty);
      expect(hapticSongs.first, 'document');
      expect(_hapticsAnalyzer.paths, [source]);
      // A subsequent AutoMix-style metadata update keeps the same analysis.
      handler.mediaItem.add(
        handler.mediaItem.value!.copyWith(
          extras: {'source': source, 'resolvedSource': '/cache/first.flac'},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(_hapticsAnalyzer.paths, [source]);
    });

    for (final autoMix in [false, true]) {
      test(
        'first song and manual skips retain haptics (AutoMix: $autoMix)',
        () async {
          enableHaptics();
          setAutoMixEnabled(autoMix);
          await handler.setQueueAndPlay(_tracks);
          await _until(() => hapticSongs.contains('one'));
          await handler.skipToNext();
          await _until(() => hapticSongs.contains('two'));
          final beforePrevious = hapticSongs.length;
          await handler.skipToPrevious();
          await _until(() => hapticSongs.skip(beforePrevious).contains('one'));
          expect(hapticSongs.last, 'one');
          expect(_hapticsAnalyzer.paths, [
            '/one.flac',
            '/two.flac',
            '/one.flac',
          ]);
        },
      );
    }

    test(
      'ordinary completion and a subsequent skip both keep haptics',
      () async {
        enableHaptics();
        await handler.setQueueAndPlay(_tracks);
        await _until(() => hapticSongs.contains('one'));
        await _native.event('music-player', 'audio.onComplete');
        await _until(() => hapticSongs.contains('two'));
        await handler.skipToNext();
        await _until(() => hapticSongs.contains('three'));
      },
    );
  });

  group('playback failures', () {
    test('runtime error stays on the song and Play retries it', () async {
      await handler.setQueueAndPlay(_tracks);
      await _native.error('music-player');
      await _until(
        () =>
            handler.playbackState.value.processingState ==
                AudioProcessingState.error &&
            _native.playing.isEmpty,
      );
      expect(handler.playbackState.value.playing, isFalse);
      expect(
        handler.playbackState.value.errorMessage,
        contains('Audio output'),
      );
      expect(handler.mediaItem.value?.id, 'one');

      // Even a late completion from a failed output must not advance the queue.
      await _native.event('music-player', 'audio.onComplete');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(handler.playbackState.value.queueIndex, 0);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.error,
      );

      await handler.play();
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.playbackState.value.errorMessage, isNull);
      expect(handler.playbackState.value.errorCode, isNull);
      expect(_native.resumedSources, ['/one.flac', '/one.flac']);
      await _native.event('music-player', 'audio.onComplete');
      await _until(() => handler.playbackState.value.queueIndex == 1);
    });

    test('source failure is reported and can be retried', () async {
      _native.sourceFailures.add('/one.flac');
      await handler.setQueueAndPlay(_tracks);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.error,
      );
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.queueIndex, 0);
      expect(_native.resumedSources, isEmpty);

      _native.sourceFailures.clear();
      await handler.play();
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.mediaItem.value?.id, 'one');
      expect(handler.playbackState.value.errorMessage, isNull);
    });

    test('error during resume cannot be overwritten by ready state', () async {
      _native.resumeFailures.add('music-player');
      await handler.setQueueAndPlay(_tracks);
      await _until(
        () =>
            handler.playbackState.value.processingState ==
            AudioProcessingState.error,
      );
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.queueIndex, 0);
      _native.resumeFailures.clear();
      await handler.skipToNext();
      expect(handler.mediaItem.value?.id, 'two');
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.playbackState.value.errorMessage, isNull);
    });

    test(
      'failed resume from pause reports an error without throwing',
      () async {
        await handler.setQueueAndPlay(_tracks);
        await handler.pause();
        _native.resumeFailures.add('music-player');
        await handler.play();
        await _until(
          () =>
              handler.playbackState.value.processingState ==
              AudioProcessingState.error,
        );
        expect(
          handler.playbackState.value.processingState,
          AudioProcessingState.error,
        );
        expect(handler.playbackState.value.playing, isFalse);
        expect(handler.mediaItem.value?.id, 'one');
        _native.resumeFailures.clear();
        await handler.play();
        expect(handler.playbackState.value.playing, isTrue);
        expect(handler.playbackState.value.errorMessage, isNull);
      },
    );

    test('resume method failure is reported without escaping Play', () async {
      await handler.setQueueAndPlay(_tracks);
      await handler.pause();
      _native.failResumeMethod = true;
      await handler.play();
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.error,
      );
      expect(handler.playbackState.value.playing, isFalse);
      _native.failResumeMethod = false;
      await handler.play();
      expect(handler.playbackState.value.playing, isTrue);
    });
  });
}
