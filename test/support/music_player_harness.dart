import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/services/storage/app_state_database.dart';
import 'package:sistrum/services/playback/autoplay_personalization.dart';
import 'package:sistrum/services/playback/listening_statistics.dart';
import 'package:sistrum/services/playback/music_playback_deck.dart';
import 'package:sistrum/services/playback/playback_handler.dart';
import 'package:sistrum/services/playback/music_player_service.dart';
import 'package:sistrum/services/playback/music_player_session_restore.dart';
import 'package:sistrum/services/library/source_deletion_events.dart';
import 'package:sistrum/services/playback/music_player_runtime.dart';
import 'package:sistrum/services/library/library_database.dart';

/// Fake playback collaborators shared by the music player tests. They are
/// copied from `music_player_runtime_test.dart`, which keeps its own private
/// copies.

class FakeDeck implements MusicPlaybackDeck {
  @override
  PlayerState state = PlayerState.stopped;
  final volumes = <double>[];
  Map<String, bool>? outputOptions;
  Duration position = Duration.zero;
  int disposals = 0;
  bool failStop = false;
  bool failPause = false;
  Completer<void>? sourceBarrier;
  Completer<void>? resumeBarrier;
  Completer<void>? cancellationBarrier;
  final cancellationStarted = Completer<void>();
  final seeks = <Duration>[];
  final sources = <String>[];
  final sourceStarted = Completer<void>();
  Completer<void> resumeStarted = Completer<void>();

  @override
  bool get isDirect => false;
  @override
  bool get needsSourceReload => false;
  @override
  Stream<PlayerState> get onPlayerStateChanged => const Stream.empty();
  @override
  Stream<Duration> get onPositionChanged => const Stream.empty();
  @override
  Stream<Duration> get onDurationChanged => const Stream.empty();
  @override
  Stream<void> get onPlayerComplete => const Stream.empty();
  @override
  set positionUpdater(PositionUpdater updater) {}
  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {}
  @override
  Future<void> setAudioContext(AudioContext context) async {}
  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);
  @override
  Future<void> cancelPreparation() async {
    final barrier = cancellationBarrier;
    if (barrier == null) return;
    if (!cancellationStarted.isCompleted) cancellationStarted.complete();
    await barrier.future;
  }

  @override
  Future<void> stop() async {
    if (failStop) throw StateError('Transport failed');
    state = PlayerState.stopped;
  }

  @override
  Future<void> pause() async {
    if (failPause) throw StateError('Pause failed');
    state = PlayerState.paused;
  }

  @override
  Future<void> resume() async {
    if (!resumeStarted.isCompleted) resumeStarted.complete();
    await resumeBarrier?.future;
    state = PlayerState.playing;
  }

  @override
  Future<void> seek(Duration value) async {
    seeks.add(value);
    position = value;
  }

  @override
  Future<Duration?> getDuration() async => const Duration(seconds: 60);
  @override
  Future<Duration?> getCurrentPosition() async => position;
  @override
  Future<void> dispose() async => disposals++;
  @override
  Future<void> setSource(
    DeviceFileSource source, {
    bool preferBitPerfect = false,
    bool directUsb = false,
    bool allowDop = false,
    bool requiresDsd = false,
    bool allowFixedVolume = false,
    bool dapExclusive = false,
  }) async {
    sources.add(source.path);
    if (!sourceStarted.isCompleted) sourceStarted.complete();
    await sourceBarrier?.future;
    outputOptions = {
      'bitPerfect': preferBitPerfect,
      'direct': directUsb,
      'dop': allowDop,
      'fixedVolume': allowFixedVolume,
      'exclusive': dapExclusive,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCompletionDeck extends FakeDeck {
  final completions = StreamController<void>.broadcast();

  @override
  Stream<void> get onPlayerComplete => completions.stream;

  @override
  Future<void> dispose() async {
    await completions.close();
    await super.dispose();
  }
}

class FakeAudioSession implements AudioSession {
  int configurations = 0;
  final activations = <bool>[];
  Completer<void>? configureBarrier;
  final interruptions = StreamController<AudioInterruptionEvent>.broadcast();

  Future<void> dispose() => interruptions.close();

  @override
  Future<void> configure(AudioSessionConfiguration configuration) async {
    configurations++;
    await configureBarrier?.future;
  }

  @override
  Future<bool> setActive(
    bool active, {
    AVAudioSessionSetActiveOptions? avAudioSessionSetActiveOptions,
    AndroidAudioFocusGainType? androidAudioFocusGainType,
    AndroidAudioAttributes? androidAudioAttributes,
    bool? androidWillPauseWhenDucked,
    AudioSessionConfiguration fallbackConfiguration =
        const AudioSessionConfiguration.music(),
  }) async {
    activations.add(active);
    return true;
  }

  @override
  Stream<AudioInterruptionEvent> get interruptionEventStream =>
      interruptions.stream;
  @override
  Stream<void> get becomingNoisyEventStream => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSessionStore implements AppStateDatabase {
  /// Every session the player asked to save, oldest first.
  final saved = <Map<String, dynamic>>[];

  @override
  Future<void> clearPlaybackSession() async {}

  @override
  Future<void> savePlaybackSession(Map<String, dynamic> session) async {
    saved.add(session);
  }

  @override
  Future<bool> updatePlaybackSessionState({
    required int index,
    required int positionMs,
    required bool shuffle,
    required String repeatMode,
  }) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDeletionHandler extends MusicPlayerHandler {
  FakeDeletionHandler(MusicPlayerRuntime runtime) : super(runtime: runtime);

  final deletedSources = <String>[];

  @override
  Future<void> onSourceDeleted(String source) async =>
      deletedSources.add(source);
}

class FakeRecorder extends ListeningRecorder {
  FakeRecorder({
    required super.write,
    required super.elapsed,
    required super.now,
  });

  int updates = 0;
  ListeningTrack? latestTrack;

  @override
  void update(
    ListeningTrack? track, {
    required bool playing,
    bool ended = false,
  }) {
    updates++;
    latestTrack = track;
    super.update(track, playing: playing, ended: ended);
  }
}

MusicPlayerRuntime musicPlayerRuntimeFor({
  AppSettings settings = const AppSettings(pauseOnMute: false),
  Future<PlaybackHandler> Function(PlaybackHandler Function())? initialize,
  List<FakeDeck>? decks,
  MusicPlaybackDeck Function(String)? createDeck,
  Stream<double> volumeChanges = const Stream.empty(),
  SourceDeletionEvents? sourceDeletionEvents,
  ListeningRecorder? recorder,
  AutoplayPersonalization Function()? createPersonalization,
  FakeAudioSession? session,
  FakeSessionStore? sessionStore,
}) {
  final audioSession = session ?? FakeAudioSession();
  addTearDown(audioSession.dispose);
  final runtime = MusicPlayerRuntime(
    settings: settings,
    dependencies: PlaybackDependencies(
      createHandler: createMusicPlayerHandler,
      restoreSession: restorePlaybackSession,
      libraryDatabase: LibraryDatabase.instance,
      createPersonalization:
          createPersonalization ?? AutoplayPersonalization.new,
      createDeck:
          createDeck ??
          (_) {
            final deck = FakeDeck();
            decks?.add(deck);
            return deck;
          },
      audioSession: () async => audioSession,
      initializeHandler: initialize ?? (builder) async => builder(),
      readMetadata: (_, {displayName}) async => {
        'replaygain_track_gain': '-6 dB',
      },
      sessionDatabase: sessionStore ?? FakeSessionStore(),
      recorder:
          recorder ??
          ListeningRecorder(
            write: (_) async {},
            elapsed: () => Duration.zero,
            now: () => DateTime(2026),
          ),
      volumeChanges: volumeChanges,
      sourceDeletionEvents: sourceDeletionEvents ?? SourceDeletionEvents(),
      isAndroid: false,
    ),
  );
  addTearDown(runtime.dispose);
  return runtime;
}

Future<void> settleMusicPlayer() => Future<void>.delayed(Duration.zero);
