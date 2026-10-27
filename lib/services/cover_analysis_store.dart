import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:sistrum/services/library_database.dart';
import 'package:sistrum/theme/cover_colors.dart';
import 'package:sistrum/utils/logger.dart';

/// Persists cover analyses, so a cover analysed once shows its colours
/// without decoding it again.
abstract class CoverAnalysisStore {
  /// The analysis stored under [key] (a cover path and file version).
  Future<CoverAnalysis?> read(String key);

  Future<void> write(String key, CoverAnalysis analysis);
}

/// A derived table in the library database, created on first use like the
/// search index, so no schema version is needed. Bounded to [maxRows].
class LibraryCoverAnalysisStore implements CoverAnalysisStore {
  LibraryCoverAnalysisStore({LibraryDatabase? database})
    : _database = database ?? LibraryDatabase.instance;

  static const table = 'cover_analysis';
  static const maxRows = 4000;
  static final _log = AppLogger('CoverAnalysisStore');

  final LibraryDatabase _database;
  Future<bool>? _ready;

  Future<bool> _ensureTable() => _ready ??= () async {
    try {
      final db = await _database.database;
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $table (
          key TEXT PRIMARY KEY,
          analysis TEXT NOT NULL,
          stored_at INTEGER NOT NULL
        )
      ''');
      return true;
    } catch (error) {
      _log.w('Cover analysis cache unavailable: $error');
      return false;
    }
  }();

  @override
  Future<CoverAnalysis?> read(String key) async {
    if (!await _ensureTable()) return null;
    try {
      final db = await _database.database;
      final rows = await db.query(
        table,
        columns: ['analysis'],
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return CoverAnalysis.fromJson(
        jsonDecode(rows.first['analysis'] as String),
      );
    } catch (_) {
      // The database may have been recreated without the derived table.
      _ready = null;
      return null;
    }
  }

  @override
  Future<void> write(String key, CoverAnalysis analysis) async {
    if (!await _ensureTable()) return;
    try {
      final db = await _database.database;
      await db.insert(table, {
        'key': key,
        'analysis': jsonEncode(analysis.toJson()),
        'stored_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      // Old cover versions and removed files age out.
      await db.execute(
        'DELETE FROM $table WHERE key NOT IN '
        '(SELECT key FROM $table ORDER BY stored_at DESC LIMIT ?)',
        [maxRows],
      );
    } catch (error) {
      _ready = null;
      _log.w('Could not store cover analysis: $error');
    }
  }
}
