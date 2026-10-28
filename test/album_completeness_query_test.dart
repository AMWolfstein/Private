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
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/screens/library/queue_tab.dart';
import 'package:sistrum/widgets/library_track_selection_bar.dart';
import 'package:sistrum/widgets/app_alert_dialog.dart';
import 'package:sistrum/widgets/library_selection_playback_actions.dart';
import 'package:sistrum/services/library_database.dart';
import 'support/material_test_theme.dart';

String _definition(String file, String table) => RegExp(
  'CREATE TABLE $table\\s*\\([\\s\\S]*?\\n\\s*\\)',
).firstMatch(File(file).readAsStringSync())!.group(0)!;

// Execute the actual page/count queries with their bound parameters in SQLite.
// Schema/bootstrap calls are isolated from this fixed inventory fixture.
Set<String>? _visibleTrackIds;

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
        'library': _definition('lib/services/library_schema.dart', 'library'),
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
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    _visibleTrackIds = null;
    SharedPreferences.setMockInitialValues({});
    final previousFactory = databaseFactoryOrNull;
    databaseFactory = databaseFactorySqflitePlugin;
    addTearDown(() => databaseFactory = previousFactory);
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => '/test/documents');
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    const sqliteChannel = MethodChannel('com.tekartik.sqflite');
    final versions = <int, int>{};
    final executor = _QueryFixture();
    messenger.setMockMethodCallHandler(sqliteChannel, (call) async {
      final args = (call.arguments as Map?) ?? {};
      if (call.method == 'openDatabase') {
        final id = versions.length + 1;
        versions[id] = LibraryDatabase.schemaVersion;
        return {'id': id};
      }
      final sql = args['sql'] as String? ?? '';
      if (call.method == 'execute') {
        if (sql.contains('CREATE VIRTUAL TABLE')) {
          throw PlatformException(
            code: 'sqlite_error',
            message: 'no such module: fts5',
          );
        }
        return null;
      }
      if (call.method != 'query') return null;
      final rows = sql.toLowerCase().contains('pragma user_version')
          ? <Map<String, Object?>>[
              {'user_version': versions[args['id']]},
            ]
          : await executor.rawQuery(
              sql,
              (args['arguments'] as List?)?.cast<Object?>(),
            );
      final columns = rows.isEmpty ? <String>[] : rows.first.keys.toList();
      return {
        'columns': columns,
        'rows': [
          for (final row in rows) [for (final column in columns) row[column]],
        ],
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(sqliteChannel, null));
  });

  testWidgets('Albums section filters metadata, supports search and can be reset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tabActive = ValueNotifier(true);
    addTearDown(tabActive.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          localLibraryProvider.overrideWith(_Local.new),
          libraryCollectionsProvider.overrideWith(_Collections.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ValueListenableBuilder<bool>(
            valueListenable: tabActive,
            builder: (_, active, _) => Scaffold(
              body: TickerMode(
                enabled: active,
                child: const QueueTab(librarySection: 'albums'),
              ),
            ),
          ),
        ),
      ),
    );
    await _waitFor(tester, find.text('Filters').hitTestable());
    await _waitFor(tester, find.text('complete').hitTestable());
    await tester.tap(find.text('Filters').hitTestable());
    await tester.pump(const Duration(milliseconds: 400));
    // Every fixture file is FLAC. Other formats must still be selectable,
    // rather than disappearing when they are absent from the loaded page.
    for (final label in [
      'M4A / MP4',
      'AAC',
      'ALAC',
      'OPUS',
      'OGG',
      'WAV',
      'AIFF',
      'WavPack',
      'DSF',
      'DFF',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Has ReplayGain'), findsOneWidget);
    await tester.ensureVisible(find.text('M4A / MP4'));
    await _waitFor(tester, find.text('M4A / MP4').hitTestable());
    await tester.tap(find.text('M4A / MP4'));
    await tester.ensureVisible(find.text('Has ReplayGain'));
    await _waitFor(tester, find.text('Has ReplayGain').hitTestable());
    await tester.tap(find.text('Has ReplayGain'));
    await tester.ensureVisible(find.text('Apply'));
    await _waitFor(tester, find.text('Apply').hitTestable());
    await tester.tap(find.text('Apply'));
    await tester.pump(const Duration(milliseconds: 400));
    await _waitFor(tester, find.text('No local albums'));
    expect(find.text('Song 1'), findsNothing);
    await tester.tap(find.text('Filters').hitTestable());
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('M4A / MP4'), findsOneWidget);
    expect(find.text('Has ReplayGain'), findsOneWidget);
    await _waitFor(tester, find.text('Reset').hitTestable());
    await tester.tap(find.text('Reset'));
    await tester.ensureVisible(find.text('Incomplete albums'));
    await _waitFor(tester, find.text('Incomplete albums').hitTestable());
    await tester.tap(find.text('Incomplete albums'));
    await tester.ensureVisible(find.text('Apply'));
    await _waitFor(tester, find.text('Apply').hitTestable());
    await tester.tap(find.text('Apply'));
    await tester.pump(const Duration(milliseconds: 400));
    await _waitFor(tester, find.text('1/12'));
    expect(find.text('2/4'), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);
    expect(find.text('complete'), findsNothing);
    expect(find.byTooltip('2/4 tracks · 2 missing'), findsOneWidget);
    expect(
      tester.widget<QueueTab>(find.byType(QueueTab)).librarySection,
      'albums',
    );

    // Pushing an album/detail route disables the underlying route's ticker.
    // Popping it must retain the current Albums section.
    final navigator = Navigator.of(tester.element(find.byType(QueueTab)));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Album details')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Album details'), findsOneWidget);
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<QueueTab>(find.byType(QueueTab)).librarySection,
      'albums',
    );
    await _waitFor(tester, find.text('1/12'));

    // Even an empty matching result must retain the filter controls.
    expect(find.text('Filters').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Filters').hitTestable());
    await tester.pump(const Duration(milliseconds: 400));
    await _waitFor(tester, find.text('Reset').hitTestable());
    await tester.tap(find.text('Reset'));
    await tester.ensureVisible(find.text('Apply'));
    await _waitFor(tester, find.text('Apply').hitTestable());
    await tester.tap(find.text('Apply'));
    await tester.pump(const Duration(milliseconds: 400));
    await _waitFor(tester, find.text('complete'));
    expect(find.text('1/12'), findsNothing);
    expect(
      tester.widget<QueueTab>(find.byType(QueueTab)).librarySection,
      'albums',
    );
    // Switching tabs also retains the current section; there is no default-view reset.
    tabActive.value = false;
    await tester.pump();
    tabActive.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<QueueTab>(find.byType(QueueTab)).librarySection,
      'albums',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    // Let any already-dispatched SQLite queries finish after provider disposal.
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
  testWidgets('Songs selection follows refreshed visible rows and search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _visibleTrackIds = {'complete1', 'complete2'};
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        localLibraryProvider.overrideWith(_Local.new),
        libraryCollectionsProvider.overrideWith(_Collections.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: QueueTab(librarySection: 'all')),
        ),
      ),
    );
    await _waitFor(tester, find.text('Song 1').hitTestable());
    await tester.longPress(find.text('Song 1').hitTestable());
    await tester.pump();
    await _waitFor(tester, find.byType(LibraryTrackSelectionBar));
    await tester.tap(find.text('Song 2').hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester
          .widget<LibraryTrackSelectionBar>(
            find.byType(LibraryTrackSelectionBar),
          )
          .selectedCount,
      2,
    );

    // A completed scan drops one selected row; the count and actions must
    // resolve the remaining visible row instead of retaining the stale ID.
    _visibleTrackIds = {'complete2'};
    (container.read(localLibraryProvider.notifier) as _Local)
        .refreshVisibleRows(1);
    await _waitFor(
      tester,
      find.byWidgetPredicate(
        (widget) =>
            widget is LibraryTrackSelectionBar && widget.selectedCount == 1,
      ),
    );
    expect(find.text('Song 1'), findsNothing);
    final bar = tester.widget<LibraryTrackSelectionBar>(
      find.byType(LibraryTrackSelectionBar),
    );
    expect(bar.allSelected, isTrue);
    expect(
      (bar.playbackActions! as LibrarySelectionPlaybackActions)
          .items
          .single
          .localItem
          .id,
      'complete2',
    );

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
  testWidgets(
    'cancelling ReplayGain restores current selection after a rescan',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      _visibleTrackIds = {'complete1', 'complete2'};
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          localLibraryProvider.overrideWith(_Local.new),
          libraryCollectionsProvider.overrideWith(_Collections.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: QueueTab(librarySection: 'all')),
          ),
        ),
      );
      await _waitFor(tester, find.text('Song 1').hitTestable());
      await tester.longPress(find.text('Song 1').hitTestable());
      await tester.pump();
      await _waitFor(tester, find.byType(LibraryTrackSelectionBar));
      final bar = tester.widget<LibraryTrackSelectionBar>(
        find.byType(LibraryTrackSelectionBar),
      );
      expect(bar.selectedCount, 1);
      bar.onReplayGain(remove: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AppAlertDialog), findsOneWidget);
      expect(find.byType(LibraryTrackSelectionBar), findsNothing);

      // The query refresh settles while the dialog suppresses selection UI.
      // Cancelling must not restore its captured, now-deleted selected row.
      _visibleTrackIds = {'complete2'};
      (container.read(localLibraryProvider.notifier) as _Local)
          .refreshVisibleRows(1);
      for (var attempt = 0; attempt < 40; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('Song 1').evaluate().isEmpty) break;
      }
      expect(find.text('Song 1'), findsNothing);
      expect(find.text('Song 2'), findsOneWidget);
      expect(find.byType(AppAlertDialog), findsOneWidget);
      final l10n = AppLocalizations.of(tester.element(find.byType(QueueTab)));
      await tester.tap(find.widgetWithText(AppDialogAction, l10n.dialogCancel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.byType(AppAlertDialog), findsNothing);
      expect(find.byType(LibraryTrackSelectionBar), findsNothing);

      // No additional library refresh: a new selection contains only the live
      // song, with no stale count or action resurrected by dialog cancellation.
      await tester.longPress(find.text('Song 2').hitTestable());
      await tester.pump();
      await _waitFor(tester, find.byType(LibraryTrackSelectionBar));
      final currentBar = tester.widget<LibraryTrackSelectionBar>(
        find.byType(LibraryTrackSelectionBar),
      );
      expect(currentBar.selectedCount, 1);
      expect(currentBar.allSelected, isTrue);
      expect(
        (currentBar.playbackActions! as LibrarySelectionPlaybackActions)
            .items
            .single
            .localItem
            .id,
        'complete2',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      for (var attempt = 0; attempt < 10; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    },
  );
}
