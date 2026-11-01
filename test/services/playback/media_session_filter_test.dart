// SPDX-License-Identifier: LGPL-3.0-only
// Copyright 2026 zarzet and contributors; adapted from Mornye v5.3.0.
import 'dart:async';

import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/playback/notification/media_session_filter.dart';

class _Refresh { const _Refresh(); }

final _start = DateTime.utc(2026, 10, 30, 12);

Duration _seconds(num seconds) =>
    Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());

/// The OS end of the session: each request in the order it arrived, at the
/// test's time in seconds.
class _Os extends AudioServicePlatform {
  final requests = <({double at, Object request})>[];
  double now = 0;
  Object? failure;
  Completer<void>? reply;

  List<PlaybackStateMessage> get states => [
    for (final entry in requests)
      if (entry.request case SetStateRequest(:final state)) state,
  ];

  void _receive(Object request) => requests.add((at: now, request: request));

  void refresh() => _receive(const _Refresh());

  @override
  Future<void> setState(SetStateRequest request) async {
    _receive(request);
    await reply?.future;
    final error = failure;
    failure = null;
    if (error != null) throw error;
  }

  @override
  Future<void> setMediaItem(SetMediaItemRequest request) async =>
      _receive(request);

  @override
  Future<void> stopService(StopServiceRequest request) async =>
      _receive(request);

  @override
  Future<void> configure(ConfigureRequest request) async => _receive(request);

  @override
  Future<void> setQueue(SetQueueRequest request) async => _receive(request);

  @override
  Future<void> setAndroidPlaybackInfo(
    SetAndroidPlaybackInfoRequest request,
  ) async => _receive(request);

  @override
  Future<void> androidForceEnableMediaButtons(
    AndroidForceEnableMediaButtonsRequest request,
  ) async => _receive(request);

  @override
  Future<void> notifyChildrenChanged(
    NotifyChildrenChangedRequest request,
  ) async => _receive(request);

  @override
  void setHandlerCallbacks(AudioHandlerCallbacks callbacks) =>
      _receive(callbacks);
}

List<MediaControlMessage> _controls({bool playing = true, bool loved = false}) {
  return [
    MediaControlMessage(
      androidIcon: loved
          ? 'drawable/ic_notification_star_filled'
          : 'drawable/ic_notification_star',
      label: loved ? 'Remove from Loved' : 'Add to Loved',
      action: MediaActionMessage.custom,
      customAction: CustomMediaActionMessage(name: 'favorite'),
    ),
    const MediaControlMessage(
      androidIcon: 'drawable/ic_widget_previous',
      label: 'Previous',
      action: MediaActionMessage.skipToPrevious,
    ),
    MediaControlMessage(
      androidIcon: playing
          ? 'drawable/ic_widget_pause'
          : 'drawable/ic_widget_play',
      label: playing ? 'Pause' : 'Play',
      action: playing ? MediaActionMessage.pause : MediaActionMessage.play,
    ),
    const MediaControlMessage(
      androidIcon: 'drawable/ic_widget_next',
      label: 'Next',
      action: MediaActionMessage.skipToNext,
    ),
  ];
}

const _systemActions = {
  MediaActionMessage.seek,
  MediaActionMessage.seekForward,
  MediaActionMessage.seekBackward,
  MediaActionMessage.skipToPrevious,
  MediaActionMessage.skipToNext,
};

/// A state as the player publishes it: [position] seconds at [at] seconds.
PlaybackStateMessage _state(
  num position, {
  num at = 0,
  bool playing = true,
  AudioProcessingStateMessage processingState =
      AudioProcessingStateMessage.ready,
  double speed = 1,
  int? queueIndex = 0,
  List<MediaControlMessage>? controls,
  List<int> compactIndices = const [1, 2, 3],
  Set<MediaActionMessage> systemActions = _systemActions,
  Duration bufferedPosition = Duration.zero,
  int? errorCode,
  String? errorMessage,
  AudioServiceRepeatModeMessage repeatMode = AudioServiceRepeatModeMessage.none,
  AudioServiceShuffleModeMessage shuffleMode =
      AudioServiceShuffleModeMessage.none,
  bool captioningEnabled = false,
}) => PlaybackStateMessage(
  processingState: processingState,
  playing: playing,
  controls: controls ?? _controls(playing: playing),
  androidCompactActionIndices: compactIndices,
  systemActions: systemActions,
  updatePosition: _seconds(position),
  bufferedPosition: bufferedPosition,
  speed: speed,
  updateTime: _start.add(_seconds(at)),
  errorCode: errorCode,
  errorMessage: errorMessage,
  repeatMode: repeatMode,
  shuffleMode: shuffleMode,
  captioningEnabled: captioningEnabled,
  queueIndex: queueIndex,
);

SetStateRequest _request(PlaybackStateMessage state) =>
    SetStateRequest(state: state);

SetMediaItemRequest _item(String id) => SetMediaItemRequest(
  mediaItem: MediaItemMessage(id: id, title: id),
);

/// A player publishing what `MusicPlayerHandler` publishes, to the OS
/// [filtered] through a [MediaSessionFilter] and to the OS [today] directly,
/// with the engine's true position.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('holds back position updates the OS advances itself', () {
    final os = _Os();
    final filter = MediaSessionFilter(os);
    for (var tick = 0; tick <= 100; tick++) {
      // Polled up to 30 ms late, as the deck reports.
      final late = const [0.0, 0.03, 0.01][tick % 3];
      unawaited(
        filter.setState(_request(_state(tick * 0.6 - late, at: tick * 0.6))),
      );
    }
    expect(os.states, hasLength(1));
  });

  test('passes on every change the OS cannot work out', () {
    final changes = <String, PlaybackStateMessage>{
      'pause': _state(10, at: 10, playing: false),
      'loading': _state(
        10,
        at: 10,
        processingState: AudioProcessingStateMessage.loading,
      ),
      'buffering': _state(
        10,
        at: 10,
        processingState: AudioProcessingStateMessage.buffering,
      ),
      'completed': _state(
        10,
        at: 10,
        processingState: AudioProcessingStateMessage.completed,
      ),
      'speed': _state(10, at: 10, speed: 1.04),
      'track': _state(10, at: 10, queueIndex: 1),
      'repeat': _state(
        10,
        at: 10,
        repeatMode: AudioServiceRepeatModeMessage.all,
      ),
      'shuffle': _state(
        10,
        at: 10,
        shuffleMode: AudioServiceShuffleModeMessage.all,
      ),
      'error': _state(10, at: 10, errorCode: 1, errorMessage: 'failed'),
      'buffered': _state(10, at: 10, bufferedPosition: _seconds(30)),
      'captions': _state(10, at: 10, captioningEnabled: true),
      'system actions': _state(10, at: 10, systemActions: const {}),
      'compact controls': _state(10, at: 10, compactIndices: const [0, 1, 2]),
      'favorite control': _state(10, at: 10, controls: _controls(loved: true)),
      'custom action': _state(
        10,
        at: 10,
        controls: [
          MediaControlMessage(
            androidIcon: 'drawable/ic_notification_star',
            label: 'Add to Loved',
            action: MediaActionMessage.custom,
            customAction: CustomMediaActionMessage(
              name: 'favorite',
              extras: const {'song': 'two'},
            ),
          ),
          ..._controls().skip(1),
        ],
      ),
    };
    for (final MapEntry(key: change, value: state) in changes.entries) {
      final os = _Os();
      final filter = MediaSessionFilter(os);
      unawaited(filter.setState(_request(_state(0))));
      unawaited(filter.setState(_request(_state(9.4, at: 9.4))));
      unawaited(filter.setState(_request(state)));
      expect(os.states.last, same(state), reason: change);
      expect(os.states, hasLength(2), reason: change);
    }
  });

  test('passes on a position that leaves the advancing one', () {
    final os = _Os();
    final filter = MediaSessionFilter(os);
    unawaited(filter.setState(_request(_state(30, at: 0))));
    // A seek of less than the tolerance stays within it.
    unawaited(filter.setState(_request(_state(40.4, at: 10))));
    expect(os.states, hasLength(1));
    final seek = _state(90, at: 11);
    unawaited(filter.setState(_request(seek)));
    expect(os.states.last, same(seek));

    // A stall that keeps playing: the position stops while time goes on,
    // so each update corrects the OS, as each one did before.
    unawaited(filter.setState(_request(_state(91, at: 12))));
    final ticks = [
      for (var tick = 1; tick <= 3; tick++) _state(91, at: 12 + tick * 0.6),
    ];
    for (final tick in ticks) {
      unawaited(filter.setState(_request(tick)));
    }
    expect(os.states.skip(2), ticks);
  });

  test('passes on any new position while paused', () {
    final os = _Os();
    final filter = MediaSessionFilter(os);
    unawaited(filter.setState(_request(_state(34, at: 0, playing: false))));
    unawaited(filter.setState(_request(_state(34, at: 5, playing: false))));
    expect(os.states, hasLength(1));
    final seek = _state(34.1, at: 6, playing: false);
    unawaited(filter.setState(_request(seek)));
    expect(os.states.last, same(seek));
  });

  test('sends the newest state before a media item, and the next after', () {
    final os = _Os();
    final filter = MediaSessionFilter(os);
    final first = _state(0);
    final newest = _state(9.6, at: 9.6);
    unawaited(filter.setState(_request(first)));
    unawaited(filter.setState(_request(_state(9, at: 9))));
    unawaited(filter.setState(_request(newest)));
    unawaited(filter.setMediaItem(_item('cover')));
    unawaited(filter.setMediaItem(_item('duration')));
    final next = _state(10.2, at: 10.2);
    unawaited(filter.setState(_request(next)));
    unawaited(filter.setState(_request(_state(10.8, at: 10.8))));
    expect(os.requests.map((entry) => entry.request), [
      isA<SetStateRequest>().having((r) => r.state, 'state', same(first)),
      isA<SetStateRequest>().having((r) => r.state, 'state', same(newest)),
      isA<SetMediaItemRequest>(),
      isA<SetMediaItemRequest>(),
      isA<SetStateRequest>().having((r) => r.state, 'state', same(next)),
    ]);
  });

  test('sends the state after a playing one turns ready', () {
    final os = _Os();
    final filter = MediaSessionFilter(os);
    unawaited(
      filter.setState(
        _request(
          _state(0, processingState: AudioProcessingStateMessage.loading),
        ),
      ),
    );
    unawaited(filter.setState(_request(_state(0, at: 2))));
    final first = _state(0.6, at: 2.6);
    unawaited(filter.setState(_request(first)));
    unawaited(filter.setState(_request(_state(1.2, at: 3.2))));
    expect(os.states, hasLength(3));
    expect(os.states.last, same(first));
  });

  test('a failed update or a stopped session sends the next state', () async {
    final os = _Os();
    final filter = MediaSessionFilter(os);
    os.failure = StateError('detached');
    await expectLater(
      filter.setState(_request(_state(0))),
      throwsA(isA<StateError>()),
    );
    await filter.setState(_request(_state(0.6, at: 0.6)));
    expect(os.states, hasLength(2));

    await filter.stopService(const StopServiceRequest());
    await filter.setMediaItem(_item('next'));
    await filter.setState(_request(_state(1.2, at: 1.2)));
    expect(os.requests.map((entry) => entry.request).skip(2), [
      isA<StopServiceRequest>(),
      isA<SetMediaItemRequest>(),
      isA<SetStateRequest>(),
    ]);
  });

  test('passes every other request through', () async {
    final os = _Os();
    final filter = MediaSessionFilter(os);
    final callbacks = _Callbacks();
    final requests = <Object>[
      ConfigureRequest(config: AudioServiceConfigMessage()),
      const SetQueueRequest(queue: []),
      const SetAndroidPlaybackInfoRequest(
        playbackInfo: LocalAndroidPlaybackInfoMessage(),
      ),
      const AndroidForceEnableMediaButtonsRequest(),
      const NotifyChildrenChangedRequest(parentMediaId: 'root'),
    ];
    await filter.configure(requests[0] as ConfigureRequest);
    await filter.setQueue(requests[1] as SetQueueRequest);
    await filter.setAndroidPlaybackInfo(
      requests[2] as SetAndroidPlaybackInfoRequest,
    );
    await filter.androidForceEnableMediaButtons(
      requests[3] as AndroidForceEnableMediaButtonsRequest,
    );
    await filter.notifyChildrenChanged(
      requests[4] as NotifyChildrenChangedRequest,
    );
    filter.setHandlerCallbacks(callbacks);
    expect(os.requests.map((entry) => entry.request), [
      ...requests,
      same(callbacks),
    ]);
  });
}

class _Callbacks implements AudioHandlerCallbacks {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
