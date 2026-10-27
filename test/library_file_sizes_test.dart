import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/services/library_database_models.dart';
import 'package:spotiflac_android/services/library_file_sizes.dart';
import 'package:spotiflac_android/services/library_queue_store.dart';

import 'support/library_paging_fixture.dart';
import 'support/sqlite_process_database.dart';

List<String> _ids(QueueLibraryDbPage page) => [
  for (final row in page.rows) (row['item'] as Map)['id'] as String,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SqliteProcessDatabase db;
  late LibraryQueueStore store;
  late LibraryFileSizes index;
  late Map<String, int?> sizes;
  late List<String> probes;

  setUp(() async {
    db = await SqliteProcessDatabase.open();
    store = await createLibraryPagingFixture(db, albumsPerSource: 3);
    sizes = {
      for (var album = 0; album < 3; album++)
        for (var number = 1; number <= 2; number++)
          '/fixture/local-$album-$number.flac': (album + 1) * 200 + number,
    };
    sizes['/fixture/local-2-2.flac'] = null;
    probes = [];
    index = LibraryFileSizes(
      db,
      readSize: (path) async {
        probes.add(path);
        return sizes[path];
      },
    );
  });
  tearDown(() => db.close());

  for (final sort in ['size-desc', 'size-asc']) {
    test(
      '$sort orders songs with unknown sizes last and pages stably',
      () async {
        await index.refresh();
        final full = await store.trackPage(
          QueueLibraryDbQuery(limit: 100, sortMode: sort),
        );
        expect(full.rows, hasLength(6));
        final values = [
          for (final row in full.rows) (row['item'] as Map)['fileSize'] as int?,
        ];
        expect(values.last, isNull);
        final known = values.whereType<int>().toList();
        final expected = [...known]..sort();
        expect(
          known,
          sort == 'size-asc' ? expected : expected.reversed.toList(),
        );
        final pages = <String>[];
        QueueLibraryDbCursor? cursor;
        do {
          final page = await store.trackPage(
            QueueLibraryDbQuery(limit: 2, cursor: cursor, sortMode: sort),
          );
          if (page.rows.isEmpty) break;
          pages.addAll(_ids(page));
          cursor = page.nextCursor;
        } while (cursor != null && pages.length < 20);
        expect(pages, _ids(full));
      },
    );

    test('$sort orders albums by total bytes, incomplete last', () async {
      await index.refresh();
      final full = await store.albumPage(
        QueueLibraryDbQuery(limit: 100, sortMode: sort),
      );
      expect(full.rows, hasLength(3));
      expect(full.rows.last['sort_size_unknown'], 1);
      expect([
        for (final row in full.rows.take(2)) row['sort_size'] as int,
      ], sort == 'size-desc' ? [803, 403] : [403, 803]);
    });
  }

  test(
    'rows are probed once, hidden sources never, and sizes persist',
    () async {
      await index.refresh();
      expect(probes, isNot(contains('/fixture/hidden.flac')));
      expect(probes, hasLength(6));
      await LibraryFileSizes(
        db,
        readSize: (_) async => fail('cached files must not be probed'),
      ).refresh();
    },
  );

  test('scan writes invalidate a file kept at the same path', () async {
    await index.refresh();
    const path = '/fixture/local-0-1.flac';
    sizes[path] = 20;
    await db.update(
      'library',
      {'file_mod_time': 500},
      where: 'id = ?',
      whereArgs: ['local-0-1'],
    );
    probes.clear();
    await index.refresh();
    expect(probes, [path]);
    final page = await store.trackPage(
      const QueueLibraryDbQuery(limit: 1, sortMode: 'size-asc'),
    );
    expect((page.rows.single['item'] as Map)['fileSize'], 20);
  });

  test('a delayed size cannot overwrite a replacement', () async {
    await index.refresh();
    const id = 'local-0-1';
    await db.update(
      'library',
      {'file_mod_time': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    final started = Completer<void>();
    final result = Completer<int?>();
    final delayed = LibraryFileSizes(
      db,
      readSize: (_) {
        started.complete();
        return result.future;
      },
    );
    final work = delayed.refresh();
    await started.future;
    await db.update(
      'library',
      {'file_mod_time': 2},
      where: 'id = ?',
      whereArgs: [id],
    );
    result.complete(999);
    await work;
    final row = (await db.query(
      'track_file_sizes',
      where: 'item_id = ?',
      whereArgs: [id],
    )).single;
    expect(row['size_bytes'], isNull);
  });

  test('deleted tracks do not leave size records behind', () async {
    await index.refresh();
    await db.delete('library', where: 'id = ?', whereArgs: ['local-0-1']);
    expect(
      await db.query(
        'track_file_sizes',
        where: 'item_id = ?',
        whereArgs: ['local-0-1'],
      ),
      isEmpty,
    );
  });

  test('overlapping refreshes share the same probes', () async {
    await Future.wait([index.refresh(), index.refresh()]);
    expect(probes, hasLength(6));
  });

  test('unavailable sizes are retried only after a pause', () async {
    await index.refresh();
    probes.clear();
    await index.refresh();
    expect(probes, isEmpty);
    await db.update('track_file_sizes', {'checked_at': 0});
    await index.refresh();
    expect(probes, ['/fixture/local-2-2.flac']);
  });

  test('size sorts are recognized', () {
    expect(isLibrarySizeSort('size-desc'), isTrue);
    expect(isLibrarySizeSort('size-asc'), isTrue);
    expect(isLibrarySizeSort('latest'), isFalse);
  });
}
