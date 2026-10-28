import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/library_database.dart';
import 'package:sistrum/services/metadata_index_reconciler.dart';

void main() {
  late Directory tempDir;
  late List<Map<String, dynamic>> upserts;
  late List<String> upsertSources;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('metadata-index-test');
    upserts = [];
    upsertSources = [];
  });
  tearDown(() => tempDir.delete(recursive: true));

  final item = LocalLibraryItem(
    id: 'stable-id',
    sourceId: 'sd-card',
    trackName: 'Old title',
    artistName: 'Artist',
    albumName: 'Album',
    filePath: '/music/song.flac',
    coverPath: '/music/old-cover.jpg',
    scannedAt: DateTime(2026),
  );

  MetadataIndexReconciler reconciler({
    Future<Map<String, dynamic>> Function(String)? read,
    Future<Map<String, dynamic>> Function(String, String)? extractCover,
    Future<void> Function(Map<String, dynamic>, {required String sourceId})?
    upsert,
  }) => MetadataIndexReconciler(
    read: read ?? (_) async => {'title': 'New title', 'genre': 'Jazz'},
    extractCover:
        extractCover ??
        (_, path) async {
          File(path).writeAsBytesSync([1]);
          return <String, dynamic>{};
        },
    supportDirectory: () async => tempDir,
    upsert:
        upsert ??
        (json, {required sourceId}) async {
          upserts.add(json);
          upsertSources.add(sourceId);
        },
  );

  test('saved tags and a fresh cover reach the index', () async {
    String? written;
    final result = await reconciler(
      extractCover: (_, path) async {
        written = path;
        File(path).writeAsBytesSync([1, 2, 3]);
        return {'error': null};
      },
    ).reconcile(item);

    expect(result.indexed, isTrue);
    expect(upsertSources, ['sd-card']);
    final json = upserts.single;
    expect(json['trackName'], 'New title');
    expect(json['genre'], 'Jazz');
    expect(json['id'], item.id);
    expect(json['filePath'], item.filePath);
    expect(json['coverPath'], written);
    expect(written, startsWith('${tempDir.path}/library_covers/'));
  });

  test('a failed extraction keeps the previous cover reference', () async {
    final result = await reconciler(
      extractCover: (_, _) async => {'error': 'no artwork'},
    ).reconcile(item);

    expect(result.indexed, isTrue);
    expect(upserts.single['coverPath'], '/music/old-cover.jpg');
  });

  test('an unreadable file reports a stale index without writing', () async {
    final result = await reconciler(
      read: (_) async => {'error': 'unreadable'},
    ).reconcile(item);

    expect(result.failure, MetadataIndexFailure.read);
    expect(upserts, isEmpty);
  });

  test('a read exception reports a stale index', () async {
    final result = await reconciler(
      read: (_) async => throw const FileSystemException('missing'),
    ).reconcile(item);

    expect(result.failure, MetadataIndexFailure.read);
    expect(upserts, isEmpty);
  });

  test('a failed upsert reports the index failure', () async {
    final result = await reconciler(
      upsert: (_, {required sourceId}) async =>
          throw StateError('database closed'),
    ).reconcile(item);

    expect(result.failure, MetadataIndexFailure.database);
    expect(result.indexed, isFalse);
  });
}
