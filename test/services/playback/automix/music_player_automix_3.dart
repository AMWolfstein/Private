part of 'music_player_automix_test.dart';

void _registerMusicPlayerAutomix3() {
  group('USB playback transport', () {
    const methods = MethodChannel('com.amwolfstein.sistrum/usb_pcm');
    const events = MethodChannel('com.amwolfstein.sistrum/usb_pcm/events');
    late MusicPlaybackDeck deck;
    late List<String> usbCalls;
    late int token;
    late String? fallbackReason;
    late bool failResume;
    late bool fatal;
    late bool volumeBlocked;
    Map<String, dynamic>? hardwareVolume;
    late String transport;
    late Map<dynamic, dynamic> prepareArguments;
    Completer<void>? pauseReply;
    Completer<Map<String, dynamic>>? prepareReply;
    var position = 0;

    Future<void> event(String name, {int? withToken}) =>
        _native.messenger.handlePlatformMessage(
          events.name,
          const StandardMethodCodec().encodeSuccessEnvelope({
            'event': name,
            'token': withToken ?? token,
          }),
          (_) {},
        );

    setUp(() {
      usbCalls = [];
      token = 0;
      fallbackReason = null;
      failResume = false;
      fatal = false;
      volumeBlocked = false;
      hardwareVolume = null;
      transport = 'pcm';
      prepareArguments = {};
      pauseReply = null;
      prepareReply = null;
      position = 0;
      _native.messenger.setMockMethodCallHandler(events, (_) async => null);
      _native.messenger.setMockMethodCallHandler(methods, (call) async {
        usbCalls.add(call.method);
        switch (call.method) {
          case 'prepare':
            prepareArguments = call.arguments as Map;
            token = (call.arguments as Map)['token'] as int;
            if (prepareReply != null) return prepareReply!.future;
            if (fallbackReason != null) {
              return {'reason': fallbackReason, 'fatal': fatal};
            }
            return {
              'ready': true,
              'duration': 60000,
              'device': 'Test DAC',
              'sampleRate': 96000,
              'bitDepth': 24,
              'transport': transport,
              'driver': prepareArguments['direct'] == true
                  ? 'usb_direct'
                  : 'android',
              'volumeBlocked': volumeBlocked,
              if (hardwareVolume != null)
                'volume': {...hardwareVolume!, 'token': token},
            };
          case 'volume':
            expect((call.arguments as Map)['token'], token);
            return {
              ...hardwareVolume!,
              'token': token,
              'currentDb': (call.arguments as Map)['db'],
            };
          case 'position':
            return position;
          case 'seek':
            position = (call.arguments as Map)['position'] as int;
          case 'resume':
            if (failResume) throw PlatformException(code: 'route_changed');
          case 'pause':
            await pauseReply?.future;
          case 'stop':
            if (prepareReply != null && !prepareReply!.isCompleted) {
              prepareReply!.complete({'reason': 'cancelled'});
            }
        }
        return null;
      });
      deck = MusicPlaybackDeck(playerId: 'usb-test', nativeAvailable: true);
    });

    test('direct driver and DoP are explicit and passed to native', () async {
      await deck.setSource(
        DeviceFileSource('/one.dsf'),
        preferBitPerfect: true,
        directUsb: true,
        allowDop: true,
      );
      expect(prepareArguments['direct'], isTrue);
      expect(prepareArguments['allowDop'], isTrue);
    });

    test('hardware volume changes the DAC, never PCM gain', () async {
      hardwareVolume = {
        'available': true,
        'minDb': -90.0,
        'maxDb': 0.0,
        'currentDb': -40.0,
      };
      await deck.setSource(
        DeviceFileSource('/one.flac'),
        preferBitPerfect: true,
        directUsb: true,
      );
      expect(usbHardwareVolume.value?.currentDb, -40);
      await setUsbHardwareVolume(0.5);
      expect(usbHardwareVolume.value?.currentDb, -45);
      expect(usbCalls, ['prepare', 'volume']);
      expect(_native.calls.where((call) => call.$2 == 'setVolume'), isEmpty);
      await deck.stop();
      expect(usbHardwareVolume.value, isNull);
    });

    test(
      'uncontrolled DAC is blocked without ordinary full-volume fallback',
      () async {
        volumeBlocked = true;
        hardwareVolume = {'available': false};
        await deck.setSource(
          DeviceFileSource('/one.flac'),
          preferBitPerfect: true,
          directUsb: true,
        );
        await expectLater(deck.resume(), throwsA(isA<UsbOutputUnavailable>()));
        expect(usbCalls, ['prepare']);
        expect(usbAudioStatus.value.reason, 'volume_unavailable');
        expect(_native.sources['usb-test'], isNull);
        await setUsbHardwareVolume(1);
        expect(usbCalls, ['prepare']);
      },
    );

    test(
      'AAudio exclusive and fixed volume require explicit options',
      () async {
        await deck.setSource(
          DeviceFileSource('/one.wav'),
          preferBitPerfect: true,
          dapExclusive: true,
        );
        expect(prepareArguments['dapExclusive'], isTrue);
        expect(prepareArguments['allowFixedVolume'], isFalse);
        expect(prepareArguments['direct'], isFalse);
        fallbackReason = 'exclusive_unavailable';
        await deck.setSource(
          DeviceFileSource('/one.wav'),
          preferBitPerfect: true,
          dapExclusive: true,
        );
        expect(usbAudioStatus.value.reason, 'exclusive_unavailable');
        expect(deck.isDirect, isFalse);
        expect(_native.sources['usb-test'], '/one.wav');
      },
    );

    test(
      'changing tracks cancels a pending USB permission without fallback',
      () async {
        prepareReply = Completer<Map<String, dynamic>>();
        final preparing = deck.setSource(
          DeviceFileSource('/one.flac'),
          preferBitPerfect: true,
          directUsb: true,
        );
        await _until(() => usbCalls.contains('prepare'));
        await deck.cancelPreparation();
        await preparing;
        expect(usbCalls, ['prepare', 'stop']);
        expect(_native.sources['usb-test'], isNull);
        expect(deck.isDirect, isFalse);
      },
    );

    test(
      'unsupported DSD never falls back through ordinary PCM output',
      () async {
        fallbackReason = 'dsd_unsupported';
        fatal = true;
        await expectLater(
          deck.setSource(
            DeviceFileSource('/one.dsf'),
            preferBitPerfect: true,
            directUsb: true,
          ),
          throwsStateError,
        );
        expect(_native.sources['usb-test'], isNull);
        expect(usbAudioStatus.value.reason, 'dsd_unsupported');
      },
    );

    test('failed first DSD start does not switch to normal playback', () async {
      transport = 'dop';
      await deck.setSource(
        DeviceFileSource('/one.dsf'),
        preferBitPerfect: true,
        directUsb: true,
      );
      failResume = true;
      await expectLater(deck.resume(), throwsA(isA<UsbOutputUnavailable>()));
      expect(_native.sources['usb-test'], isNull);
      expect(deck.needsSourceReload, isTrue);
    });

    test('DSD without a DAC never loads a normal audio source', () async {
      fallbackReason = 'no_usb';
      await expectLater(
        deck.setSource(
          DeviceFileSource('/one.dsf'),
          preferBitPerfect: true,
          directUsb: true,
          requiresDsd: true,
        ),
        throwsA(isA<UsbDsdUnavailable>()),
      );
      expect(_native.sources['usb-test'], isNull);
    });

    tearDown(() async {
      await deck.dispose();
      _native.messenger.setMockMethodCallHandler(methods, null);
      _native.messenger.setMockMethodCallHandler(events, null);
    });

    test(
      'verified route plays, pauses and seeks without software gain or rate changes',
      () async {
        await deck.setSource(
          DeviceFileSource('/one.flac'),
          preferBitPerfect: true,
        );
        expect(usbAudioStatus.value.reason, 'ready');
        await deck.resume();
        await deck.setVolume(0.4);
        await deck.setPlaybackRate(1.1);
        expect(_native.playing, isEmpty);
        expect(usbAudioStatus.value.reason, 'active');
        expect(usbAudioStatus.value.sampleRate, 96000);
        await deck.seek(const Duration(seconds: 21));
        expect(await deck.getCurrentPosition(), const Duration(seconds: 21));
        await deck.pause();
        expect(deck.state, PlayerState.paused);
        expect(usbCalls, ['prepare', 'resume', 'seek', 'position', 'pause']);
        expect(
          _native.calls.where(
            (c) =>
                c.$1 == 'usb-test' &&
                ['setVolume', 'setPlaybackRate'].contains(c.$2),
          ),
          isEmpty,
        );
      },
    );

    test('late pause reply does not pause a newly prepared source', () async {
      await deck.setSource(
        DeviceFileSource('/one.flac'),
        preferBitPerfect: true,
      );
      await deck.resume();
      pauseReply = Completer<void>();
      final pausing = deck.pause();
      await _until(() => usbCalls.contains('pause'));
      await deck.setSource(
        DeviceFileSource('/two.flac'),
        preferBitPerfect: true,
      );
      await deck.resume();
      pauseReply!.complete();
      await pausing;
      expect(deck.state, PlayerState.playing);
      expect(usbAudioStatus.value.reason, 'active');
    });

    test('missing support falls back without reporting bit-perfect', () async {
      fallbackReason = 'no_usb';
      await deck.setSource(
        DeviceFileSource('/one.flac'),
        preferBitPerfect: true,
      );
      await deck.resume();
      expect(deck.isDirect, isFalse);
      expect(_native.playing, {'usb-test'});
      expect(usbAudioStatus.value.reason, 'no_usb');
    });

    test('unverified route falls back before starting USB audio', () async {
      failResume = true;
      await deck.setSource(
        DeviceFileSource('/one.flac'),
        preferBitPerfect: true,
      );
      await deck.resume();
      expect(deck.isDirect, isFalse);
      expect(_native.sources['usb-test'], '/one.flac');
      expect(_native.playing, {'usb-test'});
      expect(usbAudioStatus.value.reason, 'unsupported');
    });

    test(
      'direct USB failure before first sound never redirects to speaker',
      () async {
        failResume = true;
        await deck.setSource(
          DeviceFileSource('/one.flac'),
          preferBitPerfect: true,
          directUsb: true,
        );
        await expectLater(deck.resume(), throwsA(isA<UsbOutputUnavailable>()));
        expect(_native.sources['usb-test'], isNull);
        expect(_native.playing, isEmpty);
        expect(usbAudioStatus.value.reason, 'route_changed');
      },
    );

    test(
      'route loss pauses and never starts the speaker automatically',
      () async {
        await deck.setSource(
          DeviceFileSource('/one.flac'),
          preferBitPerfect: true,
        );
        await deck.resume();
        await event('paused');
        await _until(() => deck.state == PlayerState.paused);
        expect(_native.playing, isEmpty);
        expect(usbAudioStatus.value.reason, 'route_changed');
        position = 19000;
        expect(deck.needsSourceReload, isTrue);
        await expectLater(deck.resume(), throwsA(isA<PlatformException>()));
        expect(_native.playing, isEmpty);
        expect(await deck.getCurrentPosition(), const Duration(seconds: 19));
      },
    );

    test(
      'events from an old song cannot pause or complete the new song',
      () async {
        await deck.setSource(
          DeviceFileSource('/one.flac'),
          preferBitPerfect: true,
        );
        final oldToken = token;
        await deck.setSource(
          DeviceFileSource('/two.flac'),
          preferBitPerfect: true,
        );
        await deck.resume();
        var completed = 0;
        final subscription = deck.onPlayerComplete.listen((_) => completed++);
        await event('complete', withToken: oldToken);
        await event('paused', withToken: oldToken);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(deck.state, PlayerState.playing);
        expect(completed, 0);
        await event('complete');
        await _until(() => completed == 1);
        expect(deck.state, PlayerState.completed);
        await subscription.cancel();
      },
    );
  });
}
