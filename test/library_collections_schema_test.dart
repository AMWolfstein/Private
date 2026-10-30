import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/library/library_collections_schema.dart';

import 'support/sqlite_process_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the schema creates each collection table and its indexes', () async {
    final db = await SqliteProcessDatabase.open();
    addTearDown(db.close);
    await createCollectionsSchema(db, dbVersion);

    final names = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type IN ('table', 'index')",
    )).map((row) => row['name'] as String).toSet();

    expect(
      names,
      containsAll([
        tableLoved,
        tablePlaylists,
        tablePlaylistTracks,
        tableFavoriteArtists,
        'idx_${tablePlaylistTracks}_track_key',
        'idx_${tableFavoriteArtists}_added_at',
      ]),
    );
  });
}
