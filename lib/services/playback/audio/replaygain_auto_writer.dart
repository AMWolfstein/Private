import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/services/native/media_file_bridge.dart';
import 'package:sistrum/services/native/native_device.dart';
import 'package:sistrum/services/playback/audio/replaygain_service.dart';
import 'package:sistrum/services/playback/audio/replaygain_write_result.dart';
import 'package:sistrum/services/playback/autoplay/song_analysis.dart';
import 'package:sistrum/utils/logging/logger.dart';

final _log = AppLogger('ReplayGainAutoWriter');

/// Writes ReplayGain tags to Library songs that have none, one at a time in
/// the background. Runs only while the Replay Gain setting is on, and waits
/// for charging when "Only while charging" is on.
class ReplayGainAutoWriter {
  ReplayGainAutoWriter({
    LibraryDatabase? library,
    Future<List<SongAnalysisLibrarySong>> Function()? librarySongs,
    Future<bool> Function(String path)? hasTags,
    Future<ReplayGainWriteResult> Function(String path)? write,
    Future<bool> Function()? isCharging,
    Future<void> Function(Duration)? wait,
    bool? isAndroid,
  }) : _librarySongs =
           librarySongs ??
           (() => SongAnalysis.libraryOf(library ?? LibraryDatabase.instance)),
       _hasTags = hasTags ?? _hasTagsOf,
       _write = write ?? ReplayGainService.applyToFile,
       _isCharging = isCharging ?? NativeDevice.isCharging,
       _wait = wait ?? ((delay) => Future<void>.delayed(delay)),
       _android = isAndroid ?? Platform.isAndroid;

  final Future<List<SongAnalysisLibrarySong>> Function() _librarySongs;
  final Future<bool> Function(String) _hasTags;
  final Future<ReplayGainWriteResult> Function(String) _write;
  final Future<bool> Function() _isCharging;
  final Future<void> Function(Duration) _wait;
  final bool _android;

  static const _chargingRecheck = Duration(minutes: 5);

  /// Songs checked so far out of the Library's local songs.
  final ValueNotifier<SongAnalysisProgress?> progress = ValueNotifier(null);

  AppSettings? _settings;
  bool _running = false;
  bool _disposed = false;
  int _generation = 0;
  // Files a write failed on this session, so they are not retried in a loop.
  final _failed = <String>{};

  bool get _enabled => _settings?.replayGainAutoWrite ?? false;

  void configure(AppSettings settings) {
    _settings = settings;
    if (_enabled) {
      refresh();
    } else {
      _generation++;
      progress.value = null;
    }
  }

  /// Starts a sweep when the setting is on and no sweep is running. Called
  /// again when the Library changes, so new songs are picked up.
  void refresh() {
    if (_disposed || !_enabled || _running) return;
    unawaited(_sweep(++_generation));
  }

  bool _active(int generation) =>
      !_disposed && _enabled && generation == _generation;

  Future<bool> _allowed() async {
    if (!(_settings?.replayGainOnlyWhileCharging ?? true) || !_android) {
      return true;
    }
    try {
      return await _isCharging();
    } catch (_) {
      return false;
    }
  }

  Future<void> _sweep(int generation) async {
    _running = true;
    try {
      final songs = (await _librarySongs())
          .where((song) => song.local && !_failed.contains(song.path))
          .toList();
      var checked = 0;
      if (_active(generation)) {
        progress.value = SongAnalysisProgress(
          analyzed: 0,
          total: songs.length,
        );
      }
      for (final song in songs) {
        while (true) {
          if (!_active(generation)) return;
          if (await _allowed()) break;
          await _wait(_chargingRecheck);
        }
        if (!_active(generation)) return;
        if (!await _hasTags(song.path)) {
          final result = await _write(song.path);
          if (!result.isWritten) {
            _failed.add(song.path);
            _log.w('ReplayGain was not written for ${song.path}');
          }
        }
        checked++;
        if (_active(generation)) {
          progress.value = SongAnalysisProgress(
            analyzed: checked,
            total: songs.length,
          );
        }
      }
    } catch (error) {
      _log.w('ReplayGain sweep stopped: $error');
    } finally {
      _running = false;
    }
  }

  static Future<bool> _hasTagsOf(String path) async {
    final metadata = await MediaFileBridge.readFileMetadata(path);
    return (metadata['replaygain_track_gain']?.toString() ?? '').trim()
        .isNotEmpty;
  }

  Future<void> dispose() async {
    _disposed = true;
    _generation++;
    progress.dispose();
  }
}
