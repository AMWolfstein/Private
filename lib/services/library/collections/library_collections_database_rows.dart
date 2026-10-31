part of 'library_collections_database.dart';

extension _LibraryCollectionsDatabasePart2 on LibraryCollectionsDatabase {
  Future<void> _upsertEntry(
    String table,
    String prefix, {
    required String key,
    required String json,
    required String addedAt,
  }) async {
    final db = await database;
    await db.insert(table, {
      '${prefix}_key': key,
      '${prefix}_json': json,
      'added_at': addedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _deleteEntry(String table, String prefix, String key) async {
    final db = await database;
    await db.delete(table, where: '${prefix}_key = ?', whereArgs: [key]);
  }
}
