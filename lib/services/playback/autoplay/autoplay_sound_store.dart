import 'dart:io';
import 'package:sistrum/services/native/media_file_bridge.dart';
import 'package:sistrum/services/playback/autoplay/autoplay_sound_profile.dart';
import 'package:sistrum/services/playback/autoplay/song_analysis_store.dart';

/// Autoplay and the Library sweep share the same versioned SQLite records.
class AutoplaySoundStore {
  AutoplaySoundStore({SongAnalysisStore? store})
    : _store = store ?? SongAnalysisStore();
  final SongAnalysisStore _store;
  Future<(int, int)> _stamp(String source) async {
    if (source.startsWith('content://')) {
      final stat = await MediaFileBridge.safStat(source);
      final size = (stat['size'] as num?)?.toInt() ?? 0;
      final modified = (stat['modified'] as num?)?.toInt() ?? 0;
      if (size <= 0 || modified <= 0) throw StateError('Unknown SAF identity');
      return (size, modified);
    }
    final stat = await File(source).stat();
    if (stat.type != FileSystemEntityType.file) {
      throw StateError('Not a local file');
    }
    return (stat.size, stat.modified.millisecondsSinceEpoch);
  }

  Future<AutoplaySoundProfile?> load(String source) async =>
      (await loadAll([source]))[source];

  /// Query in SQLite chunks, then validate identities with bounded I/O.
  Future<Map<String, AutoplaySoundProfile>> loadAll(
    Iterable<String> sources,
  ) async {
    try {
      final paths = sources.toSet().toList();
      final records = await _store.records(paths);
      final features = await _store.features(paths);
      final result = <String, AutoplaySoundProfile>{};
      var cursor = 0;
      Future<void> worker() async {
        while (cursor < paths.length) {
          final source = paths[cursor++];
          final record = records[source];
          final vector = features[source];
          if (record == null ||
              record.failed ||
              record.version != _store.version ||
              vector == null) {
            continue;
          }
          final stamp = await this.stamp(source);
          if (stamp == null ||
              record.stamp != (size: stamp.$1, modified: stamp.$2)) {
            continue;
          }
          final profile = AutoplaySoundProfile.decode(vector);
          if (profile != null) result[source] = profile;
        }
      }

      await Future.wait(List.generate(4, (_) => worker()));
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<void> save(
    String source,
    AutoplaySoundProfile profile,
    (int, int) originalStamp,
  ) async {
    if (await stamp(source) != originalStamp) return;
    await _store.save(source, (
      size: originalStamp.$1,
      modified: originalStamp.$2,
    ), profile.vector);
  }

  Future<(int, int)?> stamp(String source) async {
    try {
      return await _stamp(source);
    } catch (_) {
      return null;
    }
  }
}
