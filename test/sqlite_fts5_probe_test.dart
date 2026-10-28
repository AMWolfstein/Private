import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sistrum/services/sqlite_helpers.dart';

class _UnavailableRuntimeExecutor extends Fake implements DatabaseExecutor {
  final statements = <String>[];

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    statements.add(sql.trim());
    if (sql.contains('CREATE VIRTUAL TABLE temp.')) {
      throw Exception('no such module: fts5');
    }
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    statements.add(sql.trim());
    return const [];
  }
}

void main() {
  test(
    'an unavailable trigram runtime reports no index and cleans its probe',
    () async {
      final db = _UnavailableRuntimeExecutor();

      final created = await createTrigramFtsIndex(
        db,
        ftsTable: 'library_fts',
        contentTable: 'library',
        triggerPrefix: 'library_fts',
      );

      expect(created, isFalse);
      expect(
        db.statements
            .where((sql) => sql.startsWith('CREATE VIRTUAL TABLE temp.'))
            .length,
        1,
      );
      expect(
        db.statements.any(
          (sql) => sql.startsWith('DROP TABLE IF EXISTS temp.'),
        ),
        isTrue,
      );
      // The capability probe failed, so no index or trigger was attempted.
      expect(
        db.statements.any(
          (sql) => sql.contains('CREATE VIRTUAL TABLE IF NOT EXISTS'),
        ),
        isFalse,
      );
    },
  );
}
