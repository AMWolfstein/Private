import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sistrum/services/native/media_file_bridge.dart';
import 'package:sistrum/services/playback/autoplay/autoplay_sound_profile.dart';

/// Small, disposable local cache. Audio edits and changed SAF documents
/// invalidate summaries; deleted or unsupported files simply have no signal.
class AutoplaySoundStore {
  Future<Directory>? _directoryFuture;

  Future<Directory> _directory() => _directoryFuture ??= _createDirectory();

  Future<Directory> _createDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(
      '${support.path}/autoplay_sound_v2',
    ).create(recursive: true);
  }

  String _key(String source) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(source)) {
      hash = ((hash ^ byte) * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16);
  }

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

  Future<AutoplaySoundProfile?> load(String source) async {
    try {
      final file = File('${(await _directory()).path}/${_key(source)}.json');
      if (!await file.exists() || await file.length() > 4096) return null;
      final data = jsonDecode(await file.readAsString());
      final stamp = await _stamp(source);
      if (data is! Map ||
          data['version'] != 2 ||
          data['source'] != source ||
          data['size'] != stamp.$1 ||
          data['modified'] != stamp.$2) {
        return null;
      }
      return AutoplaySoundProfile.decode(data['values']);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(
    String source,
    AutoplaySoundProfile profile,
    (int, int) originalStamp,
  ) async {
    try {
      if (await _stamp(source) != originalStamp) return;
      final directory = await _directory();
      final file = File('${directory.path}/${_key(source)}.json');
      final temp = File(
        '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      try {
        await temp.writeAsString(
          jsonEncode({
            'version': 2,
            'source': source,
            'size': originalStamp.$1,
            'modified': originalStamp.$2,
            'values': profile.values,
          }),
        );
        await temp.rename(file.path);
      } finally {
        if (await temp.exists()) await temp.delete();
      }
      final files = await directory
          .list()
          .where((e) => e is File && e.path.endsWith('.json'))
          .cast<File>()
          .toList();
      if (files.length <= 512) return;
      final ages = <(File, DateTime)>[];
      for (final entry in files) {
        ages.add((entry, (await entry.stat()).modified));
      }
      ages.sort((a, b) => a.$2.compareTo(b.$2));
      for (final entry in ages.take(files.length - 512)) {
        await entry.$1.delete();
      }
    } catch (_) {
      /* Optional analysis must never break playback. */
    }
  }

  Future<(int, int)?> stamp(String source) async {
    try {
      return await _stamp(source);
    } catch (_) {
      return null;
    }
  }
}
