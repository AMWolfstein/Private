import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/services/ffmpeg/ffmpeg_models.dart';
import 'package:sistrum/services/playback/audio/replaygain_progress.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/services/native/native_device.dart';
import 'package:sistrum/services/playback/audio/replaygain_service.dart';
import 'package:sistrum/services/playback/audio/replaygain_state.dart';
import 'package:sistrum/services/playback/audio/replaygain_write_result.dart';
import 'package:sistrum/services/playback/autoplay/song_analysis_store.dart'
    show SongFileStamp;
import 'package:sistrum/utils/logging/logger.dart';
import 'package:sistrum/utils/files/file_access.dart';

final _log = AppLogger('ReplayGainAutoWriter');

/// A Library song as the ReplayGain writer needs it.
typedef ReplayGainLibrarySong = ({
  String path,
  String? album,
  String? albumArtist,
  String? artist,
  bool local,
});

/// Groups songs into albums and fingerprints a set of files.
abstract final class ReplayGainLibrary {
  static Future<List<ReplayGainLibrarySong>> songsOf(
    LibraryDatabase library,
  ) async {
    final songs = <ReplayGainLibrarySong>[];
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
        songs.add((
          path: path,
          album: _text(row['albumName']),
          albumArtist: _text(row['albumArtist']),
          artist: _text(row['artistName']),
          local:
              path.isNotEmpty && (isContentUri(path) || !path.contains('://')),
        ));
      }
      if (page.rows.length < 500) break;
    }
    return songs;
  }

  /// Songs with the same album and album artist share one album gain. Songs
  /// without an album name are not grouped.
  static String? albumKeyOf(ReplayGainLibrarySong song) {
    final album = song.album;
    if (album == null) return null;
    final artist = song.albumArtist ?? song.artist ?? '';
    return '${artist.toLowerCase()}\u0000${album.toLowerCase()}';
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  /// Joins each file's path, size and modification time. Any change to the
  /// album's files, or to its membership, changes this string.
  static String? fingerprintOf(
    List<String> paths,
    Map<String, SongFileStamp> stamps,
  ) {
    final parts = <String>[];
    for (final path in paths) {
      final stamp = stamps[path];
      if (stamp == null) return null;
      parts.add('$path|${stamp.size}|${stamp.modified}');
    }
    return parts.join('\n');
  }
}

/// Measures tracks and whole albums before writing all needed tags once per
/// file. SAF documents use the same verified writer as ordinary local files.
class ReplayGainAutoWriter {
  ReplayGainAutoWriter({
    LibraryDatabase? library,
    Future<List<ReplayGainLibrarySong>> Function()? librarySongs,
    Future<SongFileStamp?> Function(String)? stamp,
    Future<Map<String, dynamic>> Function(String)? readTags,
    Future<ReplayGainResult?> Function(String)? scanTrack,
    Future<ReplayGainResult?> Function(List<String>)? scanAlbum,
    Future<ReplayGainWriteResult> Function(
      String,
      Map<String, String>,
      Future<bool> Function(),
    )?
    writeTags,
    ReplayGainState? state,
    Future<bool> Function()? isCharging,
    Future<String?> Function()? nowPlayingPath,
    Future<void> Function(Duration)? wait,
    bool? isAndroid,
  }) : _librarySongs =
           librarySongs ??
           (() =>
               ReplayGainLibrary.songsOf(library ?? LibraryDatabase.instance)),
       _stamp = stamp ?? _stampOf,
       _readTags = readTags ?? ReplayGainService.readTags,
       _scanTrack = scanTrack ?? ReplayGainService.measureTrack,
       _scanAlbum = scanAlbum ?? ReplayGainService.measureAlbum,
       _writeTags =
           writeTags ??
           ((path, fields, guard) =>
               ReplayGainService.writeTags(path, fields, mayWrite: guard)),
       _state = state ?? ReplayGainStateDb(),
       _isCharging = isCharging ?? NativeDevice.isCharging,
       _nowPlayingPath = nowPlayingPath ?? (() async => null),
       _wait = wait,
       _android = isAndroid ?? Platform.isAndroid;

  final Future<List<ReplayGainLibrarySong>> Function() _librarySongs;
  final Future<SongFileStamp?> Function(String) _stamp;
  final Future<Map<String, dynamic>> Function(String) _readTags;
  final Future<ReplayGainResult?> Function(String) _scanTrack;
  final Future<ReplayGainResult?> Function(List<String>) _scanAlbum;
  final Future<ReplayGainWriteResult> Function(
    String,
    Map<String, String>,
    Future<bool> Function(),
  )
  _writeTags;
  final ReplayGainState _state;
  final Future<bool> Function() _isCharging;
  final Future<String?> Function() _nowPlayingPath;
  final Future<void> Function(Duration)? _wait;
  final bool _android;
  final progress = ValueNotifier<ReplayGainProgress?>(null);

  AppSettings? _settings;
  bool _running = false, _disposed = false, _rerun = false;
  int _generation = 0;
  Completer<void>? _wake;
  final _failed = <String>{};
  bool get _enabled => _settings?.replayGainAutoWrite ?? false;
  bool _active(int generation) =>
      !_disposed && _enabled && generation == _generation;

  void configure(AppSettings settings) {
    if (_disposed) return;
    final wasEnabled = _enabled;
    final wasChargingOnly = _settings?.replayGainOnlyWhileCharging;
    _settings = settings;
    if (!_enabled) {
      _generation++;
      _rerun = false;
      _wake?.complete();
      _wake = null;
      progress.value = null;
    } else if (!wasEnabled) {
      _failed.clear();
      refresh();
    } else if (wasChargingOnly != settings.replayGainOnlyWhileCharging) {
      _wake?.complete();
      _wake = null;
    }
  }

  /// Index changes during a pass queue a new pass rather than being lost.
  void refresh() {
    if (_disposed || !_enabled) return;
    if (_running) {
      _rerun = true;
      return;
    }
    _rerun = false;
    unawaited(_run(++_generation));
  }

  Future<void> _sleep(Duration delay) async {
    final wake = Completer<void>();
    _wake = wake;
    Timer? timer;
    final timed = Completer<void>();
    final waiting = _wait?.call(delay) ?? (timed.future);
    if (_wait == null) timer = Timer(delay, () => timed.complete());
    try {
      await Future.any([waiting, wake.future]);
    } finally {
      timer?.cancel();
      if (identical(_wake, wake)) _wake = null;
    }
  }

  Future<bool> _mayWork(int generation, _ReplayGainPass pass) async {
    while (_active(generation)) {
      if (!(_settings?.replayGainOnlyWhileCharging ?? true) || !_android) {
        return true;
      }
      var charging = false;
      try {
        charging = await _isCharging();
      } catch (_) {
        /* A failed probe never grants permission. */
      }
      if (!_active(generation)) return false;
      if (charging) return true;
      _publish(pass, ReplayGainPhase.waitingForCharging);
      await _sleep(const Duration(minutes: 5));
    }
    return false;
  }

  void _publish(_ReplayGainPass pass, ReplayGainPhase phase) {
    if (!_active(pass.generation)) return;
    progress.value = ReplayGainProgress(
      phase: phase,
      checked: pass.checked,
      total: pass.paths.length,
      written: pass.written.length,
      unchanged: pass.unchanged.length,
      failed: pass.failed.length,
      deferred: pass.deferred.length,
      completedUnits: pass.units,
      totalUnits: pass.totalUnits,
    );
  }

  Future<void> _run(int generation) async {
    _running = true;
    try {
      while (_active(generation)) {
        final again = await _pass(generation);
        if (!again || !_active(generation)) break;
        await _sleep(const Duration(minutes: 1));
      }
    } catch (error) {
      _log.w('ReplayGain sweep stopped: $error');
      if (_active(generation)) {
        progress.value =
            (progress.value ??
                    const ReplayGainProgress(phase: ReplayGainPhase.preparing))
                .withPhase(ReplayGainPhase.failed);
      }
    } finally {
      _running = false;
      if (_rerun && !_disposed && _enabled) refresh();
    }
  }

  Future<bool> _pass(int generation) async {
    progress.value = const ReplayGainProgress(phase: ReplayGainPhase.preparing);
    final library = await _librarySongs();
    if (!_active(generation)) return false;
    final songs = {
      for (final song in library)
        if (song.local && song.path.isNotEmpty && !isCueVirtualPath(song.path))
          song.path: song,
    };
    final albums = <String, List<ReplayGainLibrarySong>>{};
    for (final song in library) {
      final key = ReplayGainLibrary.albumKeyOf(song);
      if (key != null) albums.putIfAbsent(key, () => []).add(song);
    }
    final pass = _ReplayGainPass(
      generation,
      songs.keys.toList(),
      songs.length * 2 + albums.length,
    );
    final albumFields = <String, Map<String, String>>{};
    final albumCandidates = <String, List<String>>{};

    for (final path in pass.paths) {
      if (!await _mayWork(generation, pass)) return false;
      _publish(pass, ReplayGainPhase.tracks);
      try {
        if (_failed.contains(path)) {
          pass.failed.add(path);
          continue;
        }
        if (await _nowPlayingPath() == path) {
          pass.deferred.add(path);
          continue;
        }
        final current = await _stamp(path);
        if (current == null) throw StateError('File identity unavailable');
        pass.stamps[path] = current;
        final saved = await _state.trackStamp(path);
        final tags = await _readTags(path);
        if (tags['error'] != null) {
          throw StateError('Cannot read ReplayGain tags');
        }
        final albumPeak = double.tryParse(
          tags['replaygain_album_peak']?.toString() ?? '',
        );
        if (_gain(tags['replaygain_album_gain']) != null &&
            (tags['audio_codec'] == 'opus' ||
                (albumPeak != null && albumPeak.isFinite && albumPeak >= 0))) {
          pass.existingAlbumTags.add(path);
        }
        final hasGain = _gain(tags['replaygain_track_gain']) != null;
        // No saved stamp means first observation, not evidence of a change.
        final changed = saved != null && saved != current;
        if (!hasGain || changed) {
          if (!await _mayWork(generation, pass)) return false;
          final measured = await _scanTrack(path);
          if (measured == null) throw StateError('Track measurement failed');
          pass.fields[path] = {
            'replaygain_track_gain': measured.trackGain,
            'replaygain_track_peak': measured.trackPeak,
          };
        }
      } catch (error) {
        pass.failed.add(path);
        _failed.add(path);
        _log.w('ReplayGain track check failed for $path: $error');
      } finally {
        pass.checked++;
        pass.units++;
        _publish(pass, ReplayGainPhase.tracks);
      }
    }

    for (final entry in albums.entries) {
      if (!await _mayWork(generation, pass)) return false;
      _publish(pass, ReplayGainPhase.albums);
      final paths = entry.value.map((s) => s.path).toSet().toList()..sort();
      try {
        // Do not measure a partial album after a permission failure, missing
        // file, virtual CUE member, or an unsupported remote member.
        if (entry.value.any((s) => !s.local || isCueVirtualPath(s.path)) ||
            paths.any(
              (p) =>
                  !pass.stamps.containsKey(p) ||
                  pass.failed.contains(p) ||
                  pass.deferred.contains(p),
            )) {
          continue;
        }
        final before = ReplayGainLibrary.fingerprintOf(paths, pass.stamps);
        final savedAlbum = await _state.albumFingerprint(entry.key);
        if (before == savedAlbum) continue;
        if (savedAlbum == null &&
            !paths.any(pass.fields.containsKey) &&
            paths.every(pass.existingAlbumTags.contains)) {
          await _state.saveAlbumFingerprint(entry.key, before!);
          continue;
        }
        final measured = await _scanAlbum(paths);
        if (measured == null) throw StateError('Album measurement failed');
        final fields = {
          'replaygain_album_gain': measured.trackGain,
          'replaygain_album_peak': measured.trackPeak,
        };
        albumFields[entry.key] = fields;
        albumCandidates[entry.key] = paths;
        for (final path in paths) {
          pass.fields.putIfAbsent(path, () => {}).addAll(fields);
        }
      } catch (error) {
        pass.failed.addAll(paths);
        _failed.addAll(paths);
        _log.w('ReplayGain album check failed for ${entry.key}: $error');
      } finally {
        pass.units++;
        _publish(pass, ReplayGainPhase.albums);
      }
    }

    for (final path in pass.paths) {
      if (!await _mayWork(generation, pass)) return false;
      _publish(pass, ReplayGainPhase.writing);
      try {
        if (pass.failed.contains(path) || pass.deferred.contains(path)) {
          continue;
        }
        final fields = pass.fields[path];
        if (fields == null || fields.isEmpty) {
          pass.unchanged.add(path);
        } else {
          // Rechecked after measurements and inside the service immediately
          // before editing / publishing a SAF copy, not only in the Track loop.
          Future<bool> guard() async =>
              _active(generation) &&
              await _mayWork(generation, pass) &&
              await _nowPlayingPath() != path &&
              await _stamp(path) == pass.stamps[path] &&
              _active(generation);
          if (!await guard()) {
            pass.deferred.add(path);
            continue;
          }
          final result = await _writeTags(path, fields, guard);
          if (result.failure == ReplayGainWriteFailure.deferred) {
            pass.deferred.add(path);
            continue;
          }
          if (!result.isWritten) {
            throw StateError('Tag publication failed: ${result.failure}');
          }
          pass.written.add(path);
        }
        final after = await _stamp(path);
        if (after != null) {
          pass.after[path] = after;
          // Do not stamp a successful partial album as fully processed below.
          await _state.saveTrackStamp(path, after);
        }
      } catch (error) {
        pass.failed.add(path);
        _failed.add(path);
        pass.written.remove(path);
        pass.unchanged.remove(path);
        _log.w('ReplayGain publication failed for $path: $error');
      } finally {
        pass.units++;
        _publish(pass, ReplayGainPhase.writing);
      }
    }
    if (!_active(generation)) return false;
    for (final key in albumFields.keys) {
      final paths = albumCandidates[key]!;
      if (paths.any(
        (p) =>
            !pass.written.contains(p) ||
            pass.failed.contains(p) ||
            pass.deferred.contains(p),
      )) {
        continue;
      }
      final fingerprint = ReplayGainLibrary.fingerprintOf(paths, pass.after);
      if (fingerprint != null) {
        await _state.saveAlbumFingerprint(key, fingerprint);
      }
    }
    _publish(
      pass,
      pass.deferred.isEmpty
          ? ReplayGainPhase.completed
          : ReplayGainPhase.waitingForPlayback,
    );
    return pass.deferred.isNotEmpty;
  }

  static double? _gain(Object? value) {
    final parsed = double.tryParse(
      (value?.toString() ?? '').replaceFirst(RegExp(r'\s*dB\s*$'), '').trim(),
    );
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  static Future<SongFileStamp?> _stampOf(String path) async {
    final stat = await fileStat(path);
    if (stat == null ||
        stat.size == null ||
        stat.modified == null ||
        stat.size! < 0 ||
        stat.modified!.millisecondsSinceEpoch <= 0) {
      return null;
    }
    return (size: stat.size!, modified: stat.modified!.millisecondsSinceEpoch);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _wake?.complete();
    _wake = null;
    progress.dispose();
  }
}

class _ReplayGainPass {
  _ReplayGainPass(this.generation, this.paths, this.totalUnits);
  final int generation, totalUnits;
  final List<String> paths;
  int checked = 0, units = 0;
  final written = <String>{},
      unchanged = <String>{},
      failed = <String>{},
      deferred = <String>{};
  final stamps = <String, SongFileStamp>{}, after = <String, SongFileStamp>{};
  final fields = <String, Map<String, String>>{};
  final existingAlbumTags = <String>{};
}
