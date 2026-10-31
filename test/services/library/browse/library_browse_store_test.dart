import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/services/library/database/library_database_models.dart';
import 'package:sistrum/services/library/browse/library_browse_store.dart';
import 'package:sistrum/services/library/database/library_row_mapper.dart';
import 'package:sistrum/services/library/database/library_schema.dart';

import '../../../support/sqlite_process_database.dart';

part 'library_browse_store_releases.dart';
part 'library_browse_store_counts.dart';

List<String> _tracks(LibraryBrowseDbPage page) => [
  for (final row in page.rows) '${row['source']}:${(row['item'] as Map)['id']}',
];

class _AlbumQueryDatabase implements Database {
  _AlbumQueryDatabase(this.db);

  final Database db;
  late String sql;
  List<Object?>? args;

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) {
    this.sql = sql;
    args = arguments;
    return db.rawQuery(sql, arguments);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  _registerLibraryBrowseStoreReleases();
  _registerLibraryBrowseStoreCounts();
}
