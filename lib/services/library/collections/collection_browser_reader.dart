import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:sistrum/core/models/track.dart';
import 'package:sistrum/services/library/browse/library_search.dart';

typedef BrowserPlaylist = ({String id, String name, String? cover, int count});
typedef CollectionBrowserPage = ({List<Track> tracks, bool hasMore});

/// Bounded reads of the existing collections schema, without loading UI state
/// or building a complete native snapshot just to list a car's current page.
class CollectionBrowserReader {
  const CollectionBrowserReader(this.database);
  final DatabaseExecutor database;

  Future<List<BrowserPlaylist>> playlists({
    int offset = 0,
    int limit = 200,
    String? search,
  }) async {
    if (search != null) {
      final query = LibrarySearchQuery(search);
      final matches = <BrowserPlaylist>[];
      for (var start = 0; ; start += 500) {
        final page = await playlists(offset: start, limit: 500);
        matches.addAll(page.where((p) => query.matches(p.name)));
        if (page.length < 500 || matches.length >= offset + limit) break;
      }
      return matches.skip(offset).take(limit.clamp(1, 500)).toList();
    }
    final args = <Object?>[limit.clamp(1, 500), offset < 0 ? 0 : offset];
    final rows = await database.rawQuery('''
      SELECT p.id,p.name,p.cover_image_path,
        (SELECT COUNT(*) FROM playlist_tracks pt WHERE pt.playlist_id=p.id) AS count,
        (SELECT pt.track_json FROM playlist_tracks pt WHERE pt.playlist_id=p.id
          ORDER BY pt.added_at ASC,pt.rowid ASC LIMIT 1) AS preview
      FROM playlists p WHERE EXISTS (SELECT 1 FROM playlist_tracks pt WHERE pt.playlist_id=p.id)
      ORDER BY p.created_at DESC,p.rowid DESC LIMIT ? OFFSET ?
    ''', args);
    return [
      for (final row in rows)
        (
          id: row['id'] as String,
          name: row['name'] as String? ?? '',
          count: (row['count'] as num?)?.toInt() ?? 0,
          cover: (row['cover_image_path'] as String?)?.isNotEmpty == true
              ? row['cover_image_path'] as String
              : _track(row['preview'])?.coverUrl,
        ),
    ];
  }

  Future<CollectionBrowserPage> tracks({
    String? playlistId,
    int offset = 0,
    int limit = 200,
  }) async {
    final size = limit.clamp(1, 500);
    final rows = await database.rawQuery(
      playlistId == null
          ? 'SELECT track_json FROM loved_tracks ORDER BY added_at DESC,rowid DESC LIMIT ? OFFSET ?'
          : 'SELECT track_json FROM playlist_tracks WHERE playlist_id=? ORDER BY added_at ASC,rowid ASC LIMIT ? OFFSET ?',
      [?playlistId, size, offset < 0 ? 0 : offset],
    );
    return (
      tracks: [for (final row in rows) ?_track(row['track_json'])],
      hasMore: rows.length == size,
    );
  }

  static Track? _track(Object? value) {
    if (value is! String) return null;
    try {
      final json = jsonDecode(value);
      return json is Map
          ? Track.fromJson(Map<String, dynamic>.from(json))
          : null;
    } catch (_) {
      return null;
    }
  }
}
