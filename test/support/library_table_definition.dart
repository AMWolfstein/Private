import 'package:sistrum/services/library/library_schema.dart';

import 'sqlite_process_database.dart';

/// The `library` table DDL as SQLite stores it after the production schema
/// creates it, so fixtures reuse the real definition without reading source.
Future<String> libraryTableDefinition() async {
  final db = await SqliteProcessDatabase.open();
  try {
    await LibrarySchema.create(db, LibrarySchema.version);
    final rows = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'library'",
    );
    return rows.single['sql'] as String;
  } finally {
    await db.close();
  }
}
