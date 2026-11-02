import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/services/playback/core/music_playback_deck.dart';
import 'package:sistrum/services/playback/music_player/music_player_service.dart';
import '../../../support/music_player_harness.dart';

class GaplessDeck extends FakeCompletionDeck {
  @override
  bool get supportsGapless => true;
  final positions = StreamController<Duration>.broadcast();
  final links = <MusicPlaybackDeck?>[];
  MusicPlaybackDeck? linked;
  Completer<void>? linkBarrier;
  @override
  Stream<Duration> get onPositionChanged => positions.stream;
  @override
  Future<void> setNextDeck(MusicPlaybackDeck? next) async {
    linked = next;
    links.add(next);
    if (next != null) await linkBarrier?.future;
  }

  @override
  Future<void> dispose() async {
    await positions.close();
    await super.dispose();
  }
}

const tracks = [
  PlayableMedia(
    id: 'a',
    source: '/a.flac',
    title: 'A',
    artist: 'One',
    duration: Duration(seconds: 60),
  ),
  PlayableMedia(
    id: 'b',
    source: '/b.flac',
    title: 'B',
    artist: 'Two',
    duration: Duration(seconds: 60),
  ),
  PlayableMedia(
    id: 'c',
    source: '/c.flac',
    title: 'C',
    artist: 'Three',
    duration: Duration(seconds: 60),
  ),
];

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late void Function(AppSettings) configure;

  Future<(MusicPlayerHandler, List<GaplessDeck>)> setup({
    AppSettings settings = const AppSettings(pauseOnMute: false),
  }) async {
    final decks = <GaplessDeck>[];
    final runtime = musicPlayerRuntimeFor(
      settings: settings,
      createDeck: (_) {
        final deck = GaplessDeck();
        decks.add(deck);
        return deck;
      },
    );
    configure = runtime.configure;
    final handler = await runtime.initialize() as MusicPlayerHandler;
    await handler.setQueueAndPlay(tracks);
    return (handler, decks);
  }

  test(
    'native-linked deck is adopted without reloading or seeking the song',
    () async {
      final (handler, decks) = await setup();
      final outgoing = decks.first;
      outgoing.position = const Duration(seconds: 40);
      outgoing.positions.add(outgoing.position);
      await until(() => outgoing.linked != null);
      final incoming = decks[1];
      incoming.position = const Duration(
        milliseconds: 25,
      ); // Native has already started.
      outgoing.state = PlayerState.completed;
      outgoing.completions.add(null);
      await until(() => handler.mediaItem.value?.id == 'b');
      await until(() => outgoing.disposals == 1);
      expect(incoming.sources, ['/b.flac']);
      expect(incoming.seeks, isEmpty);
      expect(incoming.state, PlayerState.playing);
      expect(
        handler.playbackState.value.position,
        greaterThanOrEqualTo(const Duration(milliseconds: 25)),
      );
      await handler.dispose();
      expect(decks.every((d) => d.disposals == 1), true);
    },
  );

  for (final action in [
    'seek',
    'pause',
    'repeat',
    'remove',
    'disable',
    'dispose',
  ]) {
    test(
      '$action unlinks the native next player and releases its deck',
      () async {
        final (handler, decks) = await setup();
        final outgoing = decks.first;
        outgoing.position = const Duration(seconds: 40);
        outgoing.positions.add(outgoing.position);
        await until(() => outgoing.linked != null);
        final incoming = decks[1];
        switch (action) {
          case 'seek':
            await handler.seek(const Duration(seconds: 20));
          case 'pause':
            await handler.pause();
          case 'repeat':
            await handler.setRepeatMode(AudioServiceRepeatMode.one);
          case 'remove':
            handler.removeQueuedItem(handler.queue.value[1]);
          case 'disable':
            configure(
              const AppSettings(pauseOnMute: false, gaplessPlayback: false),
            );
          case 'dispose':
            await handler.dispose();
        }
        await until(() => incoming.disposals == 1);
        expect(outgoing.linked, isNull);
        if (action != 'dispose') await handler.dispose();
      },
    );
  }

  test(
    'cancellation during a pending native link cannot publish its deck',
    () async {
      final (handler, decks) = await setup();
      final outgoing = decks.first;
      final barrier = Completer<void>();
      outgoing.linkBarrier = barrier;
      outgoing.position = const Duration(seconds: 40);
      outgoing.positions.add(outgoing.position);
      await until(() => outgoing.linked != null);
      await handler.seek(const Duration(seconds: 10));
      expect(outgoing.linked, isNull);
      barrier.complete();
      await until(() => decks[1].disposals == 1);
      expect(handler.mediaItem.value?.id, 'a');
      await handler.dispose();
    },
  );

  for (final settings in [
    const AppSettings(gaplessPlayback: false),
    const AppSettings(usbBitPerfect: true),
    const AppSettings(usbDirect: true),
    const AppSettings(dapExclusive: true),
  ]) {
    test(
      'direct and exclusive outputs keep the existing completion path: ${settings.toJson()}',
      () async {
        final (handler, decks) = await setup(
          settings: settings.copyWith(pauseOnMute: false),
        );
        final outgoing = decks.first;
        outgoing.position = const Duration(seconds: 40);
        outgoing.positions.add(outgoing.position);
        await settleMusicPlayer();
        expect(decks.length, 1);
        expect(outgoing.links, isEmpty);
        await handler.dispose();
      },
    );
  }
}
