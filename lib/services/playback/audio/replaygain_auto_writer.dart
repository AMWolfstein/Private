import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/services/ffmpeg/ffmpeg_replaygain.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/services/native/media_file_bridge.dart';
import 'package:sistrum/services/native/native_device.dart';
import 'package:sistrum/services/playback/audio/replaygain_service.dart';
import 'package:sistrum/services/playback/audio/replaygain_state.dart';
import 'package:sistrum/services/playback/audio/replaygain_write_result.dart';
import 'package:sistrum/services/playback/autoplay/song_analysis_store.dart'
    show SongFileStamp;
import 'package:sistrum/services/playback/autoplay/song_analysis.dart'
    show SongAnalysisProgress;
import 'package:sistrum/utils/logging/logger.dart';
import 'package:sistrum/utils/files/file_access.dart' show isCueVirtualPath;

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
          local: !path.startsWith('content://'),
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

/// Writes ReplayGain tags to Library songs in the background.
///
/// Track gain is written for each local song that has none, or whose file
/// changed since its tags were written. Album gain is written for each album
/// whose set of files changed, measured over the whole album at once. Each
/// write goes through [ReplayGainService], which keeps the audio unchanged or
/// restores the original. Only runs while the Replay Gain setting is on, and
/// waits for charging when "Only while charging" is on.
class ReplayGainAutoWriter {
  ReplayGainAutoWriter({
    LibraryDatabase? library,
    Future<List<ReplayGainLibrarySong>> Function()? librarySongs,
    Future<SongFileStamp?> Function(String path)? stamp,
    Future<bool> Function(String path)? hasTrackTags,
    Future<ReplayGainWriteResult> Function(String path)? writeTrack,
    Future<String?> Function(List<String> paths)? scanAlbumGain,
    Future<double?> Function(String path)? trackPeak,
    Future<ReplayGainWriteResult> Function(
      String path,
      String gain,
      String peak,
    )?
    writeAlbum,
    ReplayGainState? state,
    Future<bool> Function()? isCharging,
    Future<String?> Function()? nowPlayingPath,
    Future<void> Function(Duration)? wait,
    bool? isAndroid,
  }) : _librarySongs =
           librarySongs ??
           (() => ReplayGainLibrary.songsOf(
             library ?? LibraryDatabase.instance,
           )),
       _stamp = stamp ?? _stampOf,
       _hasTrackTags = hasTrackTags ?? _hasTrackTagsOf,
       _writeTrack = writeTrack ?? ReplayGainService.applyToFile,
       _scanAlbumGain = scanAlbumGain ?? _scanAlbumGainOf,
       _trackPeak = trackPeak ?? _trackPeakOf,
       _writeAlbum = writeAlbum ?? _writeAlbumOf,
       _state = state ?? ReplayGainStateDb(),
       _isCharging = isCharging ?? NativeDevice.isCharging,
       _nowPlayingPath = nowPlayingPath ?? (() async => null),
       _wait = wait ?? ((delay) => Future<void>.delayed(delay)),
       _android = isAndroid ?? Platform.isAndroid;

  final Future<List<ReplayGainLibrarySong>> Function() _librarySongs;
  final Future<SongFileStamp?> Function(String) _stamp;
  final Future<bool> Function(String) _hasTrackTags;
  final Future<ReplayGainWriteResult> Function(String) _writeTrack;
  final Future<String?> Function(List<String>) _scanAlbumGain;
  final Future<double?> Function(String) _trackPeak;
  final Future<ReplayGainWriteResult> Function(String, String, String)
  _writeAlbum;
  final ReplayGainState _state;
  final Future<bool> Function() _isCharging;
  final Future<String?> Function() _nowPlayingPath;
  final Future<void> Function(Duration) _wait;
  final bool _android;

  static const _chargingRecheck = Duration(minutes: 5);
  static const _deferredRecheck = Duration(minutes: 1);

  /// Local songs checked so far out of all local songs.
  final ValueNotifier<SongAnalysisProgress?> progress = ValueNotifier(null);

  AppSettings? _settings;
  bool _running = false;
  bool _disposed = false;
  int _generation = 0;
  // Files a track write failed on this session, so they are not retried in a
  // loop. Albums containing them are skipped too.
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
  /// again when the Library changes, so new songs and albums are picked up.
  void refresh() {
    if (_disposed || !_enabled || _running) return;
    unawaited(_run(++_generation));
  }

  bool _active(int generation) =>
      !_disposed && _enabled && generation == _generation;

  Future<bool> _mayWrite(int generation) async {
    while (true) {
      if (!_active(generation)) return false;
      if (!(_settings?.replayGainOnlyWhileCharging ?? true) || !_android) {
        return true;
      }
      var charging = false;
      try {
        charging = await _isCharging();
      } catch (_) {
        charging = false;
      }
      if (charging) return true;
      await _wait(_chargingRecheck);
    }
  }

  Future<void> _run(int generation) async {
    _running = true;
    try {
      while (true) {
        final again = await _pass(generation);
        if (!again || !_active(generation)) break;
        await _wait(_deferredRecheck);
      }
    } catch (error) {
      _log.w('ReplayGain sweep stopped: $error');
    } finally {
      _running = false;
    }
  }

  /// One full pass. Returns true when some files were skipped because they
  /// were playing, so another pass is needed later.
  Future<bool> _pass(int generation) async {
    final songs = (await _librarySongs())
        .where((song) => song.local && !_failed.contains(song.path))
        .toList();
    if (!_active(generation)) return false;

    final deferred = <String>{};
    final stamps = <String, SongFileStamp>{};
    if (_active(generation)) {
      progress.value = SongAnalysisProgress(analyzed: 0, total: songs.length);
    }

    // Track gain first, so album gain is measured from tagged files.
    var checked = 0;
    for (final song in songs) {
      if (!await _mayWrite(generation)) return false;
      final current = await _stamp(song.path);
      if (current != null) stamps[song.path] = current;
      final saved = await _state.trackStamp(song.path);
      final changed = current != null && saved != current;
      if (changed || !await _hasTrackTags(song.path)) {
        if (await _nowPlayingPath() == song.path) {
          deferred.add(song.path);
        } else {
          final result = await _writeTrack(song.path);
          if (result.isWritten) {
            final written = await _stamp(song.path);
            if (written != null) {
              await _state.saveTrackStamp(song.path, written);
              stamps[song.path] = written;
            }
          } else {
            _failed.add(song.path);
            _log.w('ReplayGain track tags not written for ${song.path}');
          }
        }
      } else if (current != null && saved == null) {
        await _state.saveTrackStamp(song.path, current);
      }
      checked++;
      if (_active(generation)) {
        progress.value = SongAnalysisProgress(
          analyzed: checked,
          total: songs.length,
        );
      }
    }

    // Album gain: one measurement per album whose set of files changed.
    final albums = <String, List<String>>{};
    for (final song in songs) {
      final key = ReplayGainLibrary.albumKeyOf(song);
      if (key == null || !song.path.startsWith('/')) continue;
      albums.putIfAbsent(key, () => []).add(song.path);
    }
    for (final entry in albums.entries) {
      if (!await _mayWrite(generation)) return false;
      final paths = entry.value..sort();
      if (paths.any(deferred.contains) || paths.any(_failed.contains)) {
        continue;
      }
      if (paths.any((path) => !stamps.containsKey(path))) continue;
      final before = ReplayGainLibrary.fingerprintOf(paths, stamps);
      if (before == null) continue;
      if (await _state.albumFingerprint(entry.key) == before) continue;

      final gain = await _scanAlbumGain(paths);
      if (gain == null) {
        _log.w('ReplayGain album measurement failed for ${entry.key}');
        continue;
      }
      var peak = 0.0;
      var peaksKnown = true;
      for (final path in paths) {
        final value = await _trackPeak(path);
        if (value == null) {
          peaksKnown = false;
          break;
        }
        if (value > peak) peak = value;
      }
      if (!peaksKnown) continue;

      var ok = true;
      for (final path in paths) {
        if (!await _mayWrite(generation)) return false;
        final result = await _writeAlbum(path, gain, peak.toStringAsFixed(6));
        if (!result.isWritten) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;

      // The album writes changed each file, so record their new stamps and
      // the fingerprint those stamps produce.
      final after = <String, SongFileStamp>{};
      for (final path in paths) {
        final written = await _stamp(path);
        if (written != null) {
          after[path] = written;
          await _state.saveTrackStamp(path, written);
        }
      }
      final fingerprint = ReplayGainLibrary.fingerprintOf(paths, after);
      if (fingerprint != null) {
        await _state.saveAlbumFingerprint(entry.key, fingerprint);
      }
    }
    return deferred.isNotEmpty;
  }

  Future<void> dispose() async {
    _disposed = true;
    _generation++;
    progress.dispose();
  }

  static Future<SongFileStamp?> _stampOf(String path) async {
    final stat = await FileStat.stat(path);
    if (stat.type == FileSystemEntityType.notFound) return null;
    return (size: stat.size, modified: stat.modified.millisecondsSinceEpoch);
  }

  static Future<bool> _hasTrackTagsOf(String path) async {
    final metadata = await MediaFileBridge.readFileMetadata(path);
    return (metadata['replaygain_track_gain']?.toString() ?? '').trim()
        .isNotEmpty;
  }

  static Future<String?> _scanAlbumGainOf(List<String> paths) async =>
      (await FFmpegReplayGain.scanAlbum(paths))?.trackGain;

  static Future<double?> _trackPeakOf(String path) async {
    final metadata = await MediaFileBridge.readFileMetadata(path);
    return double.tryParse(
      metadata['replaygain_track_peak']?.toString() ?? '',
    );
  }

  static Future<ReplayGainWriteResult> _writeAlbumOf(
    String path,
    String gain,
    String peak,
  ) => ReplayGainService.writeAlbumTags(path, gain, peak);
}
