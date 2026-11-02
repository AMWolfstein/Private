// SPDX-License-Identifier: LGPL-3.0-only
// Copyright 2026 zarzet and contributors; adapted from Mornye v5.3.0.
import 'dart:async';
import 'dart:io';
import 'package:sistrum/core/models/local_library_item.dart';

import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/foundation.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/services/playback/automix/automix_status.dart';
import 'package:sistrum/services/playback/autoplay/autoplay_sound_signal.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/services/native/native_device.dart';
import 'package:sistrum/services/playback/autoplay/autoplay_sound_store.dart';
import 'package:sistrum/core/models/playable_media.dart';
import 'package:sistrum/services/playback/autoplay/song_analysis_store.dart';
import 'package:sistrum/services/playback/autoplay/song_feature_analyzer.dart';
import 'package:sistrum/utils/files/file_access.dart'
    show isContentUri, isCueVirtualPath;
import 'package:sistrum/utils/logging/logger.dart';

final _log = AppLogger('SongAnalysis');

/// A Library song's file, and whether it was scanned rather than downloaded.
typedef SongAnalysisLibrarySong = ({
  String path,
  Duration? duration,
  bool local,
});

/// When Library songs are analyzed in the background.
enum SongAnalysisSweep {
  /// Never: only the song playing is analyzed.
  never,

  /// While the device charges, unless the listener allows battery.
  whileCharging,

  /// At a low pace.
  always,
}

class SongAnalysisProgress {
  const SongAnalysisProgress({required this.analyzed, required this.total});

  final int analyzed, total;
}

enum _Outcome { analyzed, failed, unavailable, skipped }

/// Analyzes how each local Library song sounds, once, in the background, so
/// Autoplay can pick songs that sound like the session. One song at a time,
/// on one decoder thread, with rests several times longer than the work,
/// and never while a song has just started or AutoMix is mixing. The song
/// playing is analyzed soon after it starts, on battery too. Everything
/// stays on the device.
class SongAnalysis {
  SongAnalysis({
    LibraryDatabase? library,
    SongAnalysisStore? store,
    SongFeatureAnalyzer? analyzer,
    Future<List<SongAnalysisLibrarySong>> Function()? librarySongs,
    Future<SongFileStamp?> Function(String path)? stamp,
    Future<bool> Function()? isCharging,
    bool Function()? busy,
    ValueListenable<AutoMixStatus>? autoMix,
    Future<void> Function(Duration)? wait,
    SongAnalysisSweep? sweep,
    bool? isAndroid,
  }) : _store = store ?? SongAnalysisStore(),
       _analyzer = analyzer ?? SongFeatureAnalyzer(),
       _librarySongs =
           librarySongs ??
           (() => libraryOf(library ?? LibraryDatabase.instance)),
       _stamp = stamp ?? _stampOf,
       _isCharging = isCharging ?? NativeDevice.isCharging,
       _autoMix = autoMix ?? autoMixStatus,
       _busyOverride = busy,
       _customWait = wait,
       _wait = wait ?? ((delay) => Future<void>.delayed(delay)),
       _sweep = sweep ?? _defaultSweep(),
       _android = isAndroid ?? Platform.isAndroid;

  final SongAnalysisStore _store;
  final SongFeatureAnalyzer _analyzer;
  final Future<List<SongAnalysisLibrarySong>> Function() _librarySongs;
  final Future<SongFileStamp?> Function(String) _stamp;
  final Future<bool> Function() _isCharging;
  final bool Function()? _busyOverride;
  final ValueListenable<AutoMixStatus> _autoMix;
  final Future<void> Function(Duration) _wait;
  final Future<void> Function(Duration)? _customWait;
  final Set<Timer> _timers = {};
  final Map<Timer, Completer<void>> _waiting = {};

  Future<void> _delay(Duration delay) {
    if (_disposed) return Future.value();
    final done = Completer<void>();
    late Timer timer;
    timer = Timer(delay, () {
      _timers.remove(timer);
      _waiting.remove(timer);
      done.complete();
    });
    _timers.add(timer);
    _waiting[timer] = done;
    return done.future;
  }

  final SongAnalysisSweep _sweep;
  final bool _android;

  static const _startDelay = Duration(seconds: 90);
  static const _resumeDelay = Duration(seconds: 10);
  static const _currentDelay = Duration(seconds: 20);
  static const _busyRecheck = Duration(seconds: 15);
  static const _chargingRecheck = Duration(minutes: 5);
  static const _retryLater = Duration(hours: 1);
  static const _nextPass = Duration(minutes: 30);
  static const _minimumRest = Duration(seconds: 2);
  static const _restFactor = 4;

  /// How many Library songs are analyzed, once known.
  final progress = ValueNotifier<SongAnalysisProgress?>(null);

  AppSettings _settings = const AppSettings();
  bool _started = false, _disposed = false;
  int _clearing = 0, _progressRevision = 0;
  StreamSubscription<MediaItem?>? _nowPlaying;
  String? _currentSource;
  MediaItem? _currentItem;
  final _sinceChange = Stopwatch();
  int _sweepGeneration = 0, _currentGeneration = 0;
  Future<void> _tail = Future<void>.value();

  static SongAnalysisSweep _defaultSweep() {
    if (Platform.isAndroid) return SongAnalysisSweep.whileCharging;
    return SongAnalysisSweep.never;
  }

  static Future<List<SongAnalysisLibrarySong>> libraryOf(
    LibraryDatabase library,
  ) async {
    final songs = <SongAnalysisLibrarySong>[];
    for (var offset = 0; ; offset += 500) {
      final page = await library.getBrowseTrackPage(
        LibraryBrowseDbQuery(
          offset: offset,
          limit: 500,
          includeSingleTrackAlbums: true,
        ),
      );
      for (final envelope in page.rows) {
        final row = LocalLibraryItem.envelopeItem(envelope);
        final path = row['filePath']?.toString() ?? '';
        if (isCueVirtualPath(path)) continue;
        final seconds = (row['duration'] as num?)?.toDouble() ?? 0;
        songs.add((
          path: path,
          duration: seconds > 0
              ? Duration(milliseconds: (seconds * 1000).round())
              : null,
          local: true,
        ));
      }
      if (page.rows.length < 500) break;
    }
    return songs;
  }

  static Future<SongFileStamp?> _stampOf(String path) async {
    final stamp = await AutoplaySoundStore().stamp(path);
    return stamp == null ? null : (size: stamp.$1, modified: stamp.$2);
  }

  bool get _working =>
      _started &&
      !_disposed &&
      _clearing == 0 &&
      _settings.autoplaySoundMatching;

  SongAnalysisSweep get _policy =>
      _sweep == SongAnalysisSweep.whileCharging &&
          !_settings.songAnalysisOnlyWhileCharging
      ? SongAnalysisSweep.always
      : _sweep;

  bool _analyzable(String path) {
    if (path.isEmpty) return false;
    // Documents exist on Android only; streams have no file to analyze.
    if (isContentUri(path)) return _android;
    return path.startsWith('/') && !isCueVirtualPath(path);
  }

  /// A song started moments ago, when AutoMix analyzes it too, or AutoMix
  /// is mixing.
  bool get _busy =>
      _busyOverride?.call() ??
      (_autoMix.value != AutoMixStatus.idle ||
          (_sinceChange.isRunning && _sinceChange.elapsed < _currentDelay));

  /// Runs [action] after the analysis before it, so one runs at a time.
  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void configure(AppSettings settings) {
    final previous = _settings;
    _settings = settings;
    if (!_started || _disposed) return;
    if (!settings.autoplaySoundMatching) {
      if (previous.autoplaySoundMatching) _stop();
      return;
    }
    if (!previous.autoplaySoundMatching ||
        previous.songAnalysisOnlyWhileCharging !=
            settings.songAnalysisOnlyWhileCharging) {
      _schedule(_resumeDelay);
      if (!previous.autoplaySoundMatching && _currentItem != null) {
        final item = _currentItem;
        _currentSource = null;
        _onNowPlaying(item);
      }
    }
  }

  /// Starts sweeping the Library and following the song playing, which
  /// [nowPlaying] reports.
  void start(Stream<MediaItem?> nowPlaying) {
    if (_started || _disposed) return;
    _started = true;
    _nowPlaying = nowPlaying.listen(_onNowPlaying);
    if (_settings.autoplaySoundMatching) _schedule(_startDelay);
  }

  void _stop() {
    _sweepGeneration++;
    _currentGeneration++;
    _analyzer.cancel();
    for (final timer in _timers) {
      timer.cancel();
      _waiting[timer]?.complete();
    }
    _timers.clear();
    _waiting.clear();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _stop();
    await _nowPlaying?.cancel();
    _analyzer.dispose();
    await _tail;
  }

  void _onNowPlaying(MediaItem? item) {
    _currentItem = item;
    final source = item?.extras?['source']?.toString();
    if (source == _currentSource) return;
    _currentSource = source;
    _sinceChange
      ..reset()
      ..start();
    final generation = ++_currentGeneration;
    if (source == null || !_working || !_analyzable(source)) return;
    final song = (path: source, duration: item?.duration, local: false);
    unawaited(
      (_customWait == null ? _delay(_currentDelay) : _wait(_currentDelay)).then(
        (_) async {
          if (generation == _currentGeneration && _working) {
            await _analyze(song);
            if (_working) await refreshProgress();
          }
        },
      ),
    );
  }

  void _schedule(Duration delay) {
    final generation = ++_sweepGeneration;
    unawaited(
      (_customWait == null ? _delay(delay) : _wait(delay)).then((_) {
        if (generation == _sweepGeneration) return _sweepLibrary(generation);
      }),
    );
  }

  Future<bool> _charging() async {
    try {
      return await _isCharging();
    } catch (_) {
      return false;
    }
  }

  Future<void> _sweepLibrary(int generation) async {
    bool current() =>
        generation == _sweepGeneration &&
        _working &&
        _policy != SongAnalysisSweep.never;
    Future<bool> allowed() async =>
        current() &&
        (_policy != SongAnalysisSweep.whileCharging || await _charging());
    if (!await allowed()) {
      if (current()) _schedule(_chargingRecheck);
      return;
    }
    final List<SongAnalysisLibrarySong> work;
    try {
      work = await _plan();
    } on Object catch (error) {
      _log.w('Could not plan song analysis: $error');
      if (current()) _schedule(_retryLater);
      return;
    }
    var unavailable = 0;
    for (final song in work) {
      if (!await allowed()) {
        if (current()) _schedule(_chargingRecheck);
        return;
      }
      while (current() && _busy) {
        await (_customWait == null
            ? _delay(_busyRecheck)
            : _wait(_busyRecheck));
      }
      if (!current()) return;
      if (!await allowed()) {
        if (current()) _schedule(_chargingRecheck);
        return;
      }
      final watch = Stopwatch()..start();
      final outcome = await _analyze(song);
      if (!current()) return;
      if (outcome == _Outcome.skipped) continue;
      if (outcome == _Outcome.unavailable) {
        // A missing decoder or a host without native analysis: try later.
        if (++unavailable >= 3) {
          if (current()) _schedule(_retryLater);
          return;
        }
      } else {
        unavailable = 0;
      }
      if (outcome == _Outcome.analyzed) {
        final known = progress.value;
        if (known != null && known.analyzed < known.total) {
          progress.value = SongAnalysisProgress(
            analyzed: known.analyzed + 1,
            total: known.total,
          );
        }
      }
      await (_customWait == null
          ? _delay(_minimumRest + watch.elapsed * _restFactor)
          : _wait(_minimumRest + watch.elapsed * _restFactor));
    }
    if (current()) _schedule(_nextPass);
  }

  /// The Library songs that still need analysis; publishes the progress.
  List<SongAnalysisLibrarySong> _survey(
    List<SongAnalysisLibrarySong> songs,
    Map<String, SongAnalysisRecord> records,
  ) {
    final work = <SongAnalysisLibrarySong>[];
    var total = 0;
    for (final song in songs) {
      if (!_analyzable(song.path)) continue;
      total++;
      final record = records[song.path];
      if (record == null || record.version != _store.version || record.failed) {
        work.add(song);
      }
    }
    if (!_disposed && _clearing == 0) {
      progress.value = SongAnalysisProgress(
        analyzed: total - work.length,
        total: total,
      );
    }
    return work;
  }

  /// Library songs that still need analysis. Rows of files the Library no
  /// longer has are removed on the way.
  Future<List<SongAnalysisLibrarySong>> _plan() async {
    final revision = _progressRevision;
    final songs = await _librarySongs();
    final records = await _store.records();
    final paths = {for (final song in songs) song.path};
    await _store.remove([
      for (final path in records.keys)
        if (!paths.contains(path) && path != _currentSource) path,
    ]);
    if (_disposed || _clearing > 0 || revision != _progressRevision) return [];
    return _survey(songs, records);
  }

  /// Analyzes [song] unless this version analyzed or failed on the file as
  /// it is. Sweeps check only songs without a current analysis, so a
  /// changed file is analyzed again when it plays.
  Future<_Outcome> _analyze(SongAnalysisLibrarySong song) =>
      _exclusive(() async {
        if (!_working) return _Outcome.skipped;
        final generation = _sweepGeneration;
        final currentGeneration = _currentGeneration;
        try {
          final stamp = await _stamp(song.path);
          if (stamp == null) {
            // The file is gone.
            await _store.remove([song.path]);
            return _Outcome.skipped;
          }
          final record = (await _store.records([song.path]))[song.path];
          if (record != null &&
              record.version == _store.version &&
              record.stamp == stamp) {
            return _Outcome.skipped;
          }
          final result = await _analyzer.analyze(
            song.path,
            duration: song.duration,
          );
          if (result.retry ||
              !_working ||
              (generation != _sweepGeneration &&
                  currentGeneration != _currentGeneration)) {
            return _Outcome.unavailable;
          }
          if (await _stamp(song.path) != stamp) {
            return _Outcome.unavailable;
          }
          await _store.save(song.path, stamp, result.features);
          return result.features == null ? _Outcome.failed : _Outcome.analyzed;
        } on Object catch (error) {
          _log.w('Song analysis failed: $error');
          return _Outcome.unavailable;
        }
      });

  /// Counts the analyzed Library songs now.
  Future<void> refreshProgress() async {
    if (_disposed || _clearing > 0) return;
    final revision = _progressRevision;
    try {
      final songs = await _librarySongs();
      final records = await _store.records();
      if (!_disposed && _clearing == 0 && revision == _progressRevision) {
        _survey(songs, records);
      }
    } on Object catch (error) {
      _log.w('Could not count analyzed songs: $error');
    }
  }

  /// Forgets every analysis. While analysis is on, the Library is analyzed
  /// again from the start.
  Future<void> clear() async {
    if (_disposed) return;
    _progressRevision++;
    _clearing++;
    _stop();
    try {
      await _exclusive(_store.clear);
      final known = progress.value;
      if (known != null && !_disposed) {
        progress.value = SongAnalysisProgress(analyzed: 0, total: known.total);
      }
    } finally {
      _clearing--;
      if (_working) _schedule(_resumeDelay);
    }
  }

  /// How the songs of an Autoplay refill sound, or null while analysis is
  /// off or knows too little.
  Future<SoundAutoplaySignal?> loadSignal({
    required Iterable<PlayableMedia> session,
    required Iterable<PlayableMedia> candidates,
  }) async {
    if (_disposed || !_settings.autoplaySoundMatching) return null;
    try {
      final features = await _store.features({
        for (final item in session) item.source,
        for (final item in candidates) item.source,
      });
      return features.length < 2 ? null : SoundAutoplaySignal(features);
    } on Object catch (error) {
      _log.w('Song analysis is unavailable to Autoplay: $error');
      return null;
    }
  }
}
