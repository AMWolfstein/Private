part of 'music_player_automix_test.dart';

void _registerMusicPlayerAutomix2() {
  group('automatic playback on system volume', () {
    const events = MethodChannel(
      'com.kurenai7968.volume_controller.volume_listener_event',
    );
    late List<String> volumeCalls;

    Future<void> volume(double value) =>
        _native.messenger.handlePlatformMessage(
          events.name,
          const StandardMethodCodec().encodeSuccessEnvelope(value),
          (_) {},
        );

    setUp(() {
      volumeCalls = [];
      _native.messenger.setMockMethodCallHandler(events, (call) async {
        volumeCalls.add(call.method);
        return null;
      });
    });

    tearDown(() async {
      setPlaybackAutomationOptions(
        enabled: true,
        pauseOnMute: false,
        playOnHeadphonesConnected: false,
      );
      await Future<void>.delayed(Duration.zero);
      _native.messenger.setMockMethodCallHandler(events, null);
    });

    Future<void> enable() async {
      await handler.setQueueAndPlay(_tracks);
      setPlaybackAutomationOptions(
        enabled: true,
        pauseOnMute: true,
        playOnHeadphonesConnected: false,
      );
      await _until(() => volumeCalls.contains('listen'));
      await volume(0.5);
    }

    test(
      'mute pauses the real transport and unmute resumes the same song',
      () async {
        await enable();
        await volume(0);
        await _until(() => !handler.playbackState.value.playing);
        expect(_native.playing, isEmpty);
        final current = handler.mediaItem.value!.id;
        await volume(0.5);
        await _until(() => handler.playbackState.value.playing);
        expect(_native.playing, {'music-player'});
        expect(handler.mediaItem.value!.id, current);
      },
    );

    test('manual pause cancels automatic resume in the handler', () async {
      await enable();
      await volume(0);
      await _until(() => !handler.playbackState.value.playing);
      await handler.pause();
      await volume(0.5);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(handler.playbackState.value.playing, isFalse);
      expect(_native.playing, isEmpty);
    });

    test('manual pause wins while unmute resume is awaiting native', () async {
      await enable();
      await volume(0);
      await _until(() => !handler.playbackState.value.playing);
      final resumeCount = _native.calls
          .where((call) => call.$2 == 'resume')
          .length;
      _native.resumeGate = Completer<void>();
      await volume(0.5);
      await _until(
        () =>
            _native.calls.where((call) => call.$2 == 'resume').length >
            resumeCount,
      );
      final paused = handler.pause();
      _native.resumeGate!.complete();
      await paused;
      expect(handler.playbackState.value.playing, isFalse);
      expect(_native.playing, isEmpty);
    });

    test(
      'changing song during unmute cannot pause the replacement song',
      () async {
        await enable();
        await volume(0);
        await _until(() => !handler.playbackState.value.playing);
        final resumeCount = _native.calls
            .where((call) => call.$2 == 'resume')
            .length;
        _native.resumeGate = Completer<void>();
        await volume(0.5);
        await _until(
          () =>
              _native.calls.where((call) => call.$2 == 'resume').length >
              resumeCount,
        );
        final changed = handler.skipToNext();
        _native.resumeGate!.complete();
        await changed;
        expect(handler.mediaItem.value!.id, 'two');
        expect(handler.playbackState.value.playing, isTrue);
        expect(_native.playing, {'music-player'});
      },
    );

    test(
      'opening and closing a volume slider preserves the background listener',
      () async {
        await enable();
        final slider = SystemVolumeService.instance.changes.listen((_) {});
        await Future<void>.delayed(Duration.zero);
        await slider.cancel();
        expect(volumeCalls.where((method) => method == 'listen'), hasLength(1));
        expect(volumeCalls, isNot(contains('cancel')));
        await volume(0);
        await _until(() => !handler.playbackState.value.playing);
        expect(_native.playing, isEmpty);
      },
    );

    test('USB output bypasses system mute automation', () async {
      await enable();
      setUsbBitPerfectEnabled(true);
      await _until(() => volumeCalls.contains('cancel'));
      await volume(0);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(handler.playbackState.value.playing, isTrue);
    });
  });
}
