import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/providers/library/library_collections_provider.dart';
import 'package:sistrum/providers/library/local_library_provider.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/screens/library/section_tab/library_section_tab.dart';
import 'package:sistrum/widgets/library/library_track_selection_bar.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:sistrum/widgets/library/library_selection_playback_actions.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import '../../support/library_table_definition.dart';
import '../../support/material_test_theme.dart';

part 'album_completeness_query_filters.dart';
part 'album_completeness_query_rescan.dart';

// Execute the actual page/count queries with their bound parameters in SQLite.
// Schema/bootstrap calls are isolated from this fixed inventory fixture.
Set<String>? _visibleTrackIds;
String? _libraryTable;

class _QueryFixture {
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    final result = await Process.run('python3', [
      '-c',
      r'''
import json, sqlite3, sys
data = json.loads(sys.argv[1])
db = sqlite3.connect(':memory:')
db.row_factory = sqlite3.Row
db.execute(data['library'])
db.execute('CREATE TABLE library_sources (id TEXT PRIMARY KEY, enabled INTEGER, available INTEGER)')
db.execute("INSERT INTO library_sources VALUES ('internal',1,1)")
db.execute('CREATE VIEW library_visible AS SELECT * FROM library')
db.execute('CREATE TABLE library_path_keys (item_id TEXT, path_key TEXT)')
def add(id, album, number, total, depth=16):
    fields = dict(id=id, track_name='Song '+str(number), artist_name='Artist',
      album_name=album, album_artist='Artist', album_key=album+'|artist',
      file_path='/'+id+'.flac', track_number=number, total_tracks=total,
      disc_number=1, total_discs=1, bit_depth=depth,
      search_text=(album+' song '+str(number)+' artist').lower(),
      sort_genre='', sort_release='', sort_added=1)
    fields.update(dict(scanned_at='2026-01-01', source_id='internal',
                       track_name_norm='song '+str(number), artist_name_norm='artist', album_name_norm=album,
                       album_artist_norm='artist'))
    db.execute('INSERT INTO library ('+','.join(fields)+') VALUES ('+','.join('?' for _ in fields)+')', list(fields.values()))
    db.execute('INSERT INTO library_path_keys VALUES (?,?)', (id, fields['file_path']))
add('missing1', 'missing', 1, 4, depth=24)
add('missing2', 'missing', 2, 4)
add('complete1', 'complete', 1, 2, depth=24)
add('complete2', 'complete', 2, 2)
add('unknown1', 'unknown', 1, None)
add('one1', 'one-track', 1, 12)
add('mixed1', 'mixed', 1, 2)
add('mixed2', 'mixed', 2, 2)
add('local1', 'local-only', 1, 3)
add('local3', 'local-only', 3, 3)
if data['visibleIds'] is not None:
    keep = data['visibleIds']
    if keep:
        db.execute('DELETE FROM library WHERE id NOT IN ('+','.join('?' for _ in keep)+')', keep)
    else:
        db.execute('DELETE FROM library')
print(json.dumps([dict(row) for row in db.execute(data['sql'], data['args'])]))
''',
      jsonEncode({
        'library': _libraryTable,
        'sql': sql,
        'visibleIds': _visibleTrackIds?.toList(),
        'args': arguments ?? [],
      }),
    ]);
    if (result.exitCode != 0) {
      throw StateError('${result.stderr}\nSQL: $sql\nArgs: $arguments');
    }
    return (jsonDecode(result.stdout as String) as List)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList();
  }
}

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

class _Local extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() => LocalLibraryState(totalCount: 3);

  void refreshVisibleRows(int count) {
    state = state.copyWith(
      totalCount: count,
      loadedIndexVersion: state.loadedIndexVersion + 1,
    );
  }
}

class _Collections extends LibraryCollectionsNotifier {
  @override
  LibraryCollectionsState build() => LibraryCollectionsState(isLoaded: true);
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(
    finder,
    findsWidgets,
    reason: find
        .byType(Text)
        .evaluate()
        .map((element) => (element.widget as Text).data)
        .join(' | '),
  );
}

void main() {
  _registerAlbumCompletenessQueryFilters();
  _registerAlbumCompletenessQueryRescan();
}
