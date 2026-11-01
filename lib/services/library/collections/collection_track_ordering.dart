import 'package:sqflite/sqflite.dart';
import 'package:sistrum/services/library/database/sqlite_helpers.dart'
    as sqlite;

/// Reorders membership only; metadata and stable occurrence keys survive.
/// Existing timestamps remain the ordering contract for backups and browsers.
class CollectionTrackOrdering {
  const CollectionTrackOrdering(this.database);
  final Database database;

  Future<Map<String, DateTime>> reorder(
    List<String> keys, {
    String? playlistId,
  }) async {
    if (keys.isEmpty || keys.toSet().length != keys.length) {
      throw ArgumentError(
        'Order must contain each collection entry exactly once',
      );
    }
    return sqlite.transactionWithBusyRetry(database, (txn) async {
      final table = playlistId == null ? 'loved_tracks' : 'playlist_tracks';
      final rows = await txn.query(
        table,
        columns: ['track_key', 'added_at'],
        where: playlistId == null ? null : 'playlist_id = ?',
        whereArgs: playlistId == null ? null : [playlistId],
      );
      final membership = rows.map((r) => r['track_key']).toSet();
      if (membership.length != keys.length ||
          !keys.every(membership.contains)) {
        throw StateError(
          'Collection changed while reordering; reload and retry',
        );
      }
      final now = DateTime.now().toUtc();
      final stamps =
          rows
              .map((r) => DateTime.parse(r['added_at']! as String).toUtc())
              .toList()
            ..sort();
      final latestStart = now.subtract(Duration(milliseconds: keys.length));
      final start = stamps.first.isBefore(latestStart)
          ? stamps.first
          : latestStart;
      final end = stamps.last.isAfter(now) ? now : stamps.last;
      final times = <String, DateTime>{};
      var batch = txn.batch();
      for (final (i, key) in keys.indexed) {
        final time = playlistId == null
            ? end.subtract(Duration(milliseconds: i))
            : start.add(Duration(milliseconds: i));
        times[key] = time;
        batch.update(
          table,
          {'added_at': time.toIso8601String()},
          where: playlistId == null
              ? 'track_key = ?'
              : 'playlist_id = ? AND track_key = ?',
          whereArgs: playlistId == null ? [key] : [playlistId, key],
        );
        if ((i + 1) % 128 == 0) {
          await batch.commit(noResult: true);
          batch = txn.batch();
        }
      }
      if (keys.length % 128 != 0) {
        await batch.commit(noResult: true);
      }
      if (playlistId != null) {
        await txn.update(
          'playlists',
          {'updated_at': now.toIso8601String()},
          where: 'id = ?',
          whereArgs: [playlistId],
        );
      }
      return times;
    });
  }
}
