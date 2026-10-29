import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/services/storage/app_state_database.dart';
import 'package:sistrum/services/playback/autoplay_personalization.dart';
import 'package:sistrum/services/library/library_database.dart';
import 'package:sistrum/services/listening_statistics.dart';
import 'package:sistrum/services/playback/music_playback_deck.dart';
import 'package:sistrum/services/playback/playback_handler.dart';
import 'package:sistrum/services/platform_bridge.dart';
import 'package:sistrum/services/playback/playback_notification.dart';
import 'package:sistrum/services/playback/player_widget_service.dart';
import 'package:sistrum/services/source_deletion_events.dart';
import 'package:sistrum/services/system_volume_service.dart';
import 'package:sistrum/utils/logger.dart';

final _log = AppLogger('MusicPlayerRuntime');

/// Builds the concrete handler for a runtime. The service library supplies it,
/// so this file does not depend on the handler's implementation.
typedef PlaybackHandlerFactory =
    PlaybackHandler Function(MusicPlayerRuntime runtime);

/// Restores the persisted session into a runtime. The service library supplies it.
typedef PlaybackRestore = Future<void> Function(MusicPlayerRuntime runtime);

/// The process services used by a player. Tests can replace effects without
/// changing the queue, transport, interruption or automation algorithms.
class PlaybackDependencies {
  const PlaybackDependencies({
    required this.createHandler,
    required this.restoreSession,
    this.createDeck = _createDeck,
    this.audioSession = _getAudioSession,
    this.readMetadata = PlatformBridge.readFileMetadata,
    this.initializeHandler = _initializeAudioHandler,
    this.createPersonalization = AutoplayPersonalization.new,
    AppStateDatabase? sessionDatabase,
    LibraryDatabase? libraryDatabase,
    ListeningRecorder? recorder,
    SourceDeletionEvents? sourceDeletionEvents,
    Stream<double>? volumeChanges,
    bool? isAndroid,
  }) : _sessionDatabase = sessionDatabase,
       _libraryDatabase = libraryDatabase,
       _recorder = recorder,
       _sourceDeletionEvents = sourceDeletionEvents,
       _volumeChanges = volumeChanges,
       _isAndroid = isAndroid;

  final PlaybackHandlerFactory createHandler;
  final PlaybackRestore restoreSession;
  final MusicPlaybackDeck Function(String playerId) createDeck;
  final Future<AudioSession> Function() audioSession;
  final Future<Map<String, dynamic>> Function(String, {String? displayName})
  readMetadata;
  final Future<PlaybackHandler> Function(PlaybackHandler Function())
  initializeHandler;
  final AutoplayPersonalization Function() createPersonalization;
  final AppStateDatabase? _sessionDatabase;
  final LibraryDatabase? _libraryDatabase;
  final ListeningRecorder? _recorder;
  final SourceDeletionEvents? _sourceDeletionEvents;
  final Stream<double>? _volumeChanges;
  final bool? _isAndroid;

  AppStateDatabase get sessionDatabase =>
      _sessionDatabase ?? AppStateDatabase.instance;
  LibraryDatabase get libraryDatabase =>
      _libraryDatabase ?? LibraryDatabase.instance;
  ListeningRecorder get recorder => _recorder ?? listeningRecorder;
  SourceDeletionEvents get sourceDeletionEvents =>
      _sourceDeletionEvents ?? SourceDeletionEvents.instance;
  Stream<double> get volumeChanges =>
      _volumeChanges ?? SystemVolumeService.instance.changes;
  bool get isAndroid => _isAndroid ?? Platform.isAndroid;

  static MusicPlaybackDeck _createDeck(String playerId) =>
      MusicPlaybackDeck(playerId: playerId);
  static Future<AudioSession> _getAudioSession() => AudioSession.instance;
  static const notificationConfig = AudioServiceConfig(
    androidNotificationChannelId: 'com.amwolfstein.sistrum.playback',
    androidNotificationChannelName: 'Playback',
    androidNotificationIcon: 'drawable/ic_stat_sistrum',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
  );

  static Future<PlaybackHandler> _initializeAudioHandler(
    PlaybackHandler Function() builder,
  ) => AudioService.init(builder: builder, config: notificationConfig);
}

/// Owns a player lifetime and its latest immutable settings. Configuration is
/// available before lazy initialization and remains live while it is pending.
class MusicPlayerRuntime {
  MusicPlayerRuntime({
    AppSettings settings = const AppSettings(),
    required this.dependencies,
  }) : _settings = settings;

  final PlaybackDependencies dependencies;
  AutoplayPersonalization? _personalization;
  AutoplayPersonalization get personalization =>
      _personalization ??= dependencies.createPersonalization();
  AppSettings _settings;
  PlaybackHandler? _handler;
  void Function()? _unsubscribeSourceDeletion;
  Future<PlaybackHandler>? _initFuture;
  Future<void>? _restoreFuture;
  final _handlers = StreamController<PlaybackHandler?>.broadcast(sync: true);
  final _mutedPlaybackEvents = StreamController<void>.broadcast();
  bool _initializing = false;
  bool _disposed = false;
  Future<void>? _disposeFuture;
  String _unknownTitle = 'Unknown title', _unknownArtist = 'Unknown artist';
  PlaybackNotification _notification = const PlaybackNotification();
  Future<bool> Function(MediaItem)? _toggleFavorite;
  Future<void> Function()? exclusiveAudioHook;

  AppSettings get settings => _settings;
  PlaybackHandler? get handler => _initializing ? null : _handler;
  String get unknownTitle => _unknownTitle;
  String get unknownArtist => _unknownArtist;
  PlaybackNotification get notification => _notification;

  // Transient feedback is never replayed when a screen or app shell reopens.
  Stream<void> get mutedPlaybackEvents => _mutedPlaybackEvents.stream;

  void notifyMutedPlayback() {
    if (!_disposed) _mutedPlaybackEvents.add(null);
  }

  void configure(AppSettings settings) {
    final previous = _settings;
    _settings = settings;
    _handler?.applySettings(previous);
  }

  void updateStrings({
    required String unknownTitle,
    required String unknownArtist,
  }) {
    _unknownTitle = unknownTitle;
    _unknownArtist = unknownArtist;
  }

  void configureNotification({
    required PlaybackNotification presentation,
    required Future<bool> Function(MediaItem) toggleFavorite,
  }) {
    _notification = presentation;
    _toggleFavorite = toggleFavorite;
    _handler?.refreshNotificationControls();
  }

  Future<bool?> toggleFavorite(MediaItem item) async =>
      _toggleFavorite?.call(item);

  void updateFavorite(MediaItem item, bool loved) {
    _notification = _notification.withFavorite(item, loved);
    _handler?.refreshNotificationControls();
  }

  void attach(PlaybackHandler handler) {
    if (_disposed) throw StateError('This playback runtime was disposed');
    final existing = _handler;
    if (existing != null && !identical(existing, handler)) {
      throw StateError('This playback runtime already owns a handler');
    }
    _handler = handler;
    if (!identical(existing, handler)) {
      _unsubscribeSourceDeletion = dependencies.sourceDeletionEvents.subscribe(
        handler.onSourceDeleted,
      );
    }
    if (!_initializing && !identical(existing, handler)) _handlers.add(handler);
  }

  void detach(PlaybackHandler handler) {
    if (!identical(_handler, handler)) return;
    _unsubscribeSourceDeletion?.call();
    _unsubscribeSourceDeletion = null;
    _handler = null;
    _restoreFuture = null;
    if (!_handlers.isClosed) _handlers.add(null);
  }

  Future<PlaybackHandler> initialize() {
    if (_disposed) {
      return Future.error(StateError('This playback runtime was disposed'));
    }
    final pending = _initFuture;
    if (pending != null) return pending;
    final existing = _handler;
    if (existing != null) return Future.value(existing);
    return _initFuture = _initialize();
  }

  Future<PlaybackHandler> _initialize() async {
    _initializing = true;
    PlaybackHandler? created;
    try {
      // Defer even a synchronous test initializer until _initFuture is stored.
      await Future<void>.value();
      final handler = await dependencies.initializeHandler(() {
        if (_disposed) throw StateError('This playback runtime was disposed');
        return created = dependencies.createHandler(this);
      });
      if (_disposed || handler.isDisposed || !identical(_handler, handler)) {
        throw StateError(
          'Playback initialization returned an inactive handler',
        );
      }
      _initializing = false;
      _handlers.add(handler);
      if (dependencies.isAndroid) {
        PlayerWidgetService.instance.bind(handler);
      }
      return handler;
    } catch (error, stack) {
      _log.e('Failed to initialize playback', error, stack);
      await created?.dispose();
      rethrow;
    } finally {
      _initializing = false;
      _initFuture = null;
    }
  }

  Future<void> restoreSession() =>
      _restoreFuture ??= dependencies.restoreSession(this);

  /// The default runtime lives for the app lifetime. Scoped runtimes close
  /// subscriptions and reject new initialization when their owner disposes.
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _toggleFavorite = null;
    exclusiveAudioHook = null;
    await _handler?.dispose();
    try {
      await _initFuture;
    } catch (_) {
      // Initialization may have failed because its pending handler was closed.
    }
    await _personalization?.dispose();
    await _handlers.close();
    await _mutedPlaybackEvents.close();
  }

  Stream<T> _events<T>(
    Stream<T> Function(PlaybackHandler) select, {
    List<T> initial = const [],
  }) => Stream<T>.multi((listener) {
    StreamSubscription<T>? events;
    var revision = 0;
    void selectHandler(PlaybackHandler? handler) {
      final selectedRevision = ++revision;
      unawaited(events?.cancel());
      events = null;
      if (handler == null) {
        for (final value in initial) {
          listener.addSync(value);
        }
      } else {
        events = select(handler).listen((value) {
          if (selectedRevision == revision) listener.addSync(value);
        }, onError: listener.addErrorSync);
      }
    }

    // Register first: UI listeners can cancel immediately while initialization
    // is pending, and can follow a replacement handler after disposal.
    final ready = _handlers.stream.listen(
      selectHandler,
      onDone: listener.closeSync,
    );
    selectHandler(handler);
    listener.onCancel = () {
      revision++;
      unawaited(ready.cancel());
      unawaited(events?.cancel());
    };
  });

  Stream<MediaItem?> mediaItemEvents() =>
      _events((handler) => handler.mediaItem, initial: [null]);
  Stream<PlaybackState> playbackStateEvents() =>
      _events((handler) => handler.playbackState);
  Stream<List<MediaItem>> queueEvents() =>
      _events((handler) => handler.queue, initial: [const []]);
}
