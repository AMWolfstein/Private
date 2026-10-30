import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/services/library/database/library_database.dart';

LocalLibraryItem _song(String id, {String? path, String title = 'Song'}) =>
    LocalLibraryItem(
      id: id,
      sourceId: 'legacy',
      trackName: title,
      artistName: 'Artist',
      albumName: 'Album',
      filePath: path ?? '/music/$id.flac',
      scannedAt: DateTime.utc(2026),
      fileModTime: 1,
      trackNumber: 1,
      totalTracks: 2,
      discNumber: 1,
      totalDiscs: 1,
      bitDepth: 16,
      genre: 'Pop',
      releaseDate: '2026',
    );

Future<List<String>> _browseIds(LibraryDatabase db) async {
  final page = await db.getBrowseTrackPage(
    const LibraryBrowseDbQuery(limit: 50, offset: 0),
  );
  return [for (final row in page.rows) (row['item'] as Map)['id'] as String];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory documents;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => documents.path);
  });

  setUp(() {
    documents = Directory.systemTemp.createTempSync('library-db-');
  });

  tearDown(() async {
    await LibraryDatabase.instance.close();
    documents.deleteSync(recursive: true);
  });

  test('an upserted song is returned by the browse query', () async {
    final db = LibraryDatabase.instance;
    await db.upsert(_song('a').toJson());
    expect(await _browseIds(db), ['a']);
  });

  test('deleting a path removes only the song stored at that path', () async {
    final db = LibraryDatabase.instance;
    await db.upsert(_song('a', path: '/music/a.flac').toJson());
    await db.upsert(_song('b', path: '/music/b.flac').toJson());
    final removed = await db.deleteByPath('/music/a.flac');
    expect(removed, 1);
    expect(await _browseIds(db), ['b']);
  });

  test('deleting by id removes the song', () async {
    final db = LibraryDatabase.instance;
    await db.upsert(_song('a').toJson());
    await db.delete('a');
    expect(await _browseIds(db), isEmpty);
  });

  test('a batch upsert stores every song', () async {
    final db = LibraryDatabase.instance;
    await db.upsertBatch([
      for (final id in ['x', 'y', 'z']) _song(id).toJson(),
    ]);
    expect(await _browseIds(db), unorderedEquals(['x', 'y', 'z']));
  });

  test('replacing everything keeps only the new songs', () async {
    final db = LibraryDatabase.instance;
    await db.upsert(_song('old').toJson());
    await db.replaceAll([_song('new').toJson()]);
    expect(await _browseIds(db), ['new']);
  });
}
