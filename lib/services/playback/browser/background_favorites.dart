import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:sistrum/core/models/library_collections.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/core/models/track.dart';
import 'package:sistrum/core/models/unified_library_item.dart';
import 'package:sistrum/services/library/collections/library_collections_database.dart';
import 'package:sistrum/services/library/database/library_database.dart';

/// Shares the phone's library identity, including ISRC-backed collection keys.
Future<Track> collectionTrackForMedia(
  MediaItem item,
  LibraryDatabase library,
) async {
  final source = item.extras?['source']?.toString() ?? '';
  final row = await library.getById(item.id);
  if (row != null) {
    return UnifiedLibraryItem.fromLocalLibrary(
      LocalLibraryItem.fromJson(row),
    ).toTrack();
  }
  if (source.isNotEmpty) {
    final matches = await library.findByTrackAndArtist(
      item.title,
      item.artist ?? '',
    );
    for (final row in matches) {
      final local = LocalLibraryItem.fromJson(row);
      if (local.filePath == source) {
        return UnifiedLibraryItem.fromLocalLibrary(local).toTrack();
      }
    }
  }
  return Track(
    id: item.id,
    name: item.title,
    artistName: item.artist ?? '',
    albumName: item.album ?? '',
    coverUrl: item.artUri?.toString(),
    duration: item.duration?.inSeconds ?? 0,
    source: 'local',
  );
}

/// Headless stars use the same database as the UI. Toggle is transactional so
/// two controllers cannot both read an old value and lose the second toggle.
class BackgroundFavorites {
  BackgroundFavorites({
    required this.library,
    required this.collections,
    Future<Track> Function(MediaItem)? resolve,
  }) : _resolve = resolve;
  final LibraryDatabase library;
  final LibraryCollectionsDatabase collections;
  final Future<Track> Function(MediaItem)? _resolve;
  Future<Track> _track(MediaItem item) =>
      _resolve?.call(item) ?? collectionTrackForMedia(item, library);
  Future<bool> isLoved(MediaItem item) async {
    final key = trackCollectionKey(await _track(item));
    return (await (await collections.database).rawQuery(
      'SELECT 1 FROM loved_tracks WHERE track_key=? LIMIT 1',
      [key],
    )).isNotEmpty;
  }

  Future<bool> toggle(MediaItem item) async {
    final track = await _track(item);
    final key = trackCollectionKey(track);
    return (await collections.database).transaction((txn) async {
      final exists = (await txn.rawQuery(
        'SELECT 1 FROM loved_tracks WHERE track_key=? LIMIT 1',
        [key],
      )).isNotEmpty;
      if (exists) {
        await txn.delete(
          'loved_tracks',
          where: 'track_key=?',
          whereArgs: [key],
        );
        return false;
      }
      await txn.insert('loved_tracks', {
        'track_key': key,
        'track_json': jsonEncode(track.toJson()),
        'added_at': DateTime.now().toIso8601String(),
      });
      return true;
    });
  }
}
