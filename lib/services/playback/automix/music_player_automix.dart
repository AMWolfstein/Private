import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:sistrum/core/models/playable_media.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/services/playback/automix/automix_analysis.dart';
import 'package:sistrum/services/playback/automix/automix_analyzer.dart';
import 'package:sistrum/services/playback/automix/automix_effect_renderer.dart';
import 'package:sistrum/services/playback/automix/automix_phase_lock.dart';
import 'package:sistrum/services/playback/automix/automix_status.dart';
import 'package:sistrum/services/playback/core/music_playback_deck.dart';
import 'package:sistrum/utils/logging/logger.dart';

part 'music_player_automix_status.dart';
part 'music_player_automix_pins.dart';
part 'music_player_automix_generation.dart';
part 'music_player_automix_position.dart';
part 'music_player_automix_start.dart';
part 'music_player_automix_alignment.dart';
part 'music_player_automix_lifecycle.dart';

final _log = AppLogger('MusicPlayer');

/// What AutoMix needs from the handler: the live queue, the playing deck and the
/// transition commit. [_HandlerAutoMixHost] supplies it, so AutoMix does not
/// reach the handler's private state itself.
abstract interface class AutoMixHost {
  AppSettings get settings;
  bool get isDisposed;
  bool get sourceReady;
  bool get userPaused;
  bool get interruptionActive;
  bool get isLiveHandler;
  AudioServiceRepeatMode get repeatMode;
  int get mediaCount;
  PlayableMedia mediaAt(int index);
  int get index;
  int get playRequestGeneration;
  int get sessionQueueRevision;
  double get normalizationVolume;
  MusicPlaybackDeck get player;
  Duration? get currentDuration;
  Future<String?> resolveSource(PlayableMedia media);
  Future<double> normalizationVolumeFor(String path, {String? cacheKey});
  MusicPlaybackDeck createDeck(String playerId);
  void listenToPlayer(MusicPlaybackDeck deck);
  Future<void> disposeDeck(MusicPlaybackDeck deck);
  Future<void> cleanupPendingResolvedPaths();
  void broadcastState({PlayerState? playerState});
  void broadcastPosition(Duration position, {bool force = false});
  void commitTransition({
    required MusicPlaybackDeck incoming,
    required int index,
    required PlayableMedia next,
    required String? nextPath,
    required Duration? nextDuration,
    required double normalizationVolume,
    required Duration audiblePosition,
  });
}

class MusicAutoMix {
  MusicAutoMix(this.host, this.analyzer, this.renderer);

  final AutoMixHost host;
  final AutoMixAnalyzer analyzer;
  final AutoMixEffectRenderer renderer;
  final _preparationPins = <int, Set<String>>{};
  final _mixPins = <String>{};
  MusicPlaybackDeck? _prepared;
  MusicPlaybackDeck? _outgoing;
  MusicPlaybackDeck? _effectDry;
  MusicPlaybackDeck? _effectPrepared;
  RenderedMixTail? _effectTail;
  AutoMixPlan? _plan;
  PlayableMedia? _next;
  String? _nextPath;
  Duration? _nextDuration;
  String? _attempt;
  int _nextIndex = -1;
  int _queueRevision = -1;
  int _playGeneration = -1;
  int _generation = 0;
  int _cancelling = 0;
  bool _preparing = false;
  bool _starting = false;
  double _incomingVolume = 1;
  double rate = 1;
  Timer? _startTimer;
  Timer? _fadeTimer;
  Future<void> _fadeWrite = Future<void>.value();
  bool _writing = false;
}
