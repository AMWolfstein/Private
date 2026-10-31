import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/services/storage/app_state_database.dart';
import 'package:sistrum/services/playback/autoplay/autoplay_personalization.dart';
import 'package:sistrum/services/playback/stats/listening_statistics.dart';
import 'package:sistrum/services/playback/core/music_playback_deck.dart';
import 'package:sistrum/services/playback/core/playback_handler.dart';
import 'package:sistrum/services/playback/music_player/music_player_service.dart';
import 'package:sistrum/services/playback/music_player/music_player_session_restore.dart';
import 'package:sistrum/services/playback/notification/playback_notification.dart';
import 'package:sistrum/services/library/scan/source_deletion_events.dart';
import 'package:sistrum/utils/files/file_access.dart';
import 'package:sistrum/utils/logging/logger.dart';
import 'package:sistrum/services/playback/music_player/music_player_runtime.dart';
import 'package:sistrum/services/library/database/library_database.dart';

part 'music_player_runtime_1.dart';
part 'music_player_runtime_2.dart';
part 'music_player_runtime_3.dart';
part 'music_player_runtime_4.dart';

class _Deck implements MusicPlaybackDeck {
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

class _CompletionDeck extends _Deck {
  final completions = StreamController<void>.broadcast();

  @override
  Stream<void> get onPlayerComplete => completions.stream;

  @override
  Future<void> dispose() async {
    await completions.close();
    await super.dispose();
  }
}

class _Session implements AudioSession {
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

class _SessionStore implements AppStateDatabase {
  @override
  Future<void> clearPlaybackSession() async {}

  @override
  Future<void> savePlaybackSession(Map<String, dynamic> session) async {}
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

class _DeletionHandler extends MusicPlayerHandler {
  _DeletionHandler(MusicPlayerRuntime runtime) : super(runtime: runtime);

  final deletedSources = <String>[];

  @override
  Future<void> onSourceDeleted(String source) async =>
      deletedSources.add(source);
}

class _Recorder extends ListeningRecorder {
  _Recorder({required super.write, required super.elapsed, required super.now});

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

MusicPlayerRuntime _runtime({
  AppSettings settings = const AppSettings(pauseOnMute: false),
  Future<PlaybackHandler> Function(PlaybackHandler Function())? initialize,
  List<_Deck>? decks,
  MusicPlaybackDeck Function(String)? createDeck,
  Stream<double> volumeChanges = const Stream.empty(),
  SourceDeletionEvents? sourceDeletionEvents,
  ListeningRecorder? recorder,
  AutoplayPersonalization Function()? createPersonalization,
  _Session? session,
}) {
  final audioSession = session ?? _Session();
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
            final deck = _Deck();
            decks?.add(deck);
            return deck;
          },
      audioSession: () async => audioSession,
      initializeHandler: initialize ?? (builder) async => builder(),
      readMetadata: (_, {displayName}) async => {
        'replaygain_track_gain': '-6 dB',
      },
      sessionDatabase: _SessionStore(),
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

Future<void> _settle() => Future<void>.delayed(Duration.zero);

const _item = MediaItem(id: 'one', title: 'One');
const _track = PlayableMedia(
  id: 'one',
  source: '/one.flac',
  title: 'One',
  artist: 'Artist',
  duration: Duration(seconds: 60),
);

void main() {
  _registerMusicPlayerRuntime1();
  _registerMusicPlayerRuntime2();
  _registerMusicPlayerRuntime3();
  _registerMusicPlayerRuntime4();
}

double _adjustment(
  AutoplayPersonalization service,
  AutoplayLearningTrack track,
  AutoplayLearningTrack seed,
  DateTime at,
) =>
    service.rankingSnapshot?.rankAdjustment(track, previous: seed, at: at) ?? 0;
