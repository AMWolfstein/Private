import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/animated_artwork/animated_artwork_video.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Records what the widget asks the platform player to do. Frames never
/// arrive, so the static artwork stays on screen, as it does before the first
/// frame in the real player.
class _FakeVideoPlatform extends VideoPlayerPlatform {
  _FakeVideoPlatform({this.failCreate = false});

  final bool failCreate;
  final log = <String>[];
  final _events = <int, StreamController<VideoEvent>>{};

  /// Closes streams the tests did not dispose, so none outlives its test.
  Future<void> closeAll() async {
    for (final events in _events.values) {
      await events.close();
    }
    _events.clear();
  }

  int _next = 1;
  bool? mixWithOthers;

  @override
  Future<void> init() async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {
    this.mixWithOthers = mixWithOthers;
    log.add('mix:$mixWithOthers');
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    if (failCreate) {
      throw PlatformException(code: 'unsupported', message: 'no decoder');
    }
    final id = _next++;
    // Owned by _events; closed when the player is disposed.
    // ignore: close_sinks
    final events = StreamController<VideoEvent>.broadcast();
    _events[id] = events;
    log.add('create');
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    // ignore: close_sinks
    final events = _events[playerId]!;
    // Sent after the controller has subscribed, as the platform does.
    scheduleMicrotask(
      () => events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 8),
          size: const Size(640, 480),
        ),
      ),
    );
    return events.stream;
  }

  @override
  Future<void> dispose(int playerId) async {
    log.add('dispose');
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {
    log.add('looping:$looping');
  }

  @override
  Future<void> play(int playerId) async => log.add('play');

  @override
  Future<void> pause(int playerId) async => log.add('pause');

  @override
  Future<void> setVolume(int playerId, double volume) async {
    log.add('volume:$volume');
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildView(int playerId) => const SizedBox.expand(key: Key('video'));
}

Widget _host({
  required File file,
  bool active = true,
  bool reduceMotion = false,
  Key? key,
}) {
  return ProviderScope(
    overrides: const [],
    child: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: MaterialApp(
        home: Scaffold(
          body: AnimatedArtworkVideo(
            key: key,
            file: file,
            active: active,
            fallback: const Center(
              child: Text('static cover', key: Key('still')),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late _FakeVideoPlatform platform;
  late File file;

  setUp(() {
    platform = _FakeVideoPlatform();
    VideoPlayerPlatform.instance = platform;
    file = File('${Directory.systemTemp.path}/aa_widget_test.mp4');
  });

  tearDown(() async {
    await platform.closeAll();
  });

  testWidgets('a player that cannot start leaves the static cover in place', (
    tester,
  ) async {
    platform = _FakeVideoPlatform(failCreate: true);
    VideoPlayerPlatform.instance = platform;

    await tester.pumpWidget(_host(file: file));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('still')), findsOneWidget);
    expect(find.byType(VideoPlayer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the video is silent, looping and mixed with other audio', (
    tester,
  ) async {
    await tester.pumpWidget(_host(file: file));
    await tester.pump(const Duration(milliseconds: 50));

    expect(platform.mixWithOthers, isTrue);
    expect(
      platform.log,
      containsAll(['mix:true', 'looping:true', 'volume:0.0']),
    );
  });

  testWidgets('a playing video starts when motion is allowed', (tester) async {
    await tester.pumpWidget(_host(file: file));
    await tester.pump(const Duration(milliseconds: 50));

    expect(platform.log, contains('play'));
  });

  testWidgets('reduced motion keeps the static cover and never plays', (
    tester,
  ) async {
    await tester.pumpWidget(_host(file: file, reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 50));

    expect(platform.log, isNot(contains('play')));
    expect(find.byKey(const Key('still')), findsOneWidget);
  });

  testWidgets('an inactive video (for example under lyrics) does not play', (
    tester,
  ) async {
    await tester.pumpWidget(_host(file: file, active: false));
    await tester.pump(const Duration(milliseconds: 50));

    expect(platform.log, isNot(contains('play')));
  });

  testWidgets('leaving the tree releases the platform player', (tester) async {
    await tester.pumpWidget(_host(file: file));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.pumpWidget(const SizedBox.shrink());
    // Releasing awaits the stream cancel before the platform call.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();

    expect(platform.log, contains('dispose'));
  });

  testWidgets('no video frame is drawn before the first frame arrives', (
    tester,
  ) async {
    await tester.pumpWidget(_host(file: file));
    await tester.pump(const Duration(milliseconds: 50));

    final opacity = tester.widget<AnimatedOpacity>(
      find.byType(AnimatedOpacity),
    );
    expect(opacity.opacity, 0);
  });
}
