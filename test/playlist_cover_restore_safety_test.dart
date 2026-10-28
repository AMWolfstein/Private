import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/services/library_collections_database.dart';

class _Database implements LibraryCollectionsDatabase {
  bool fail = false;
  Map<String, dynamic> saved = {};
  String? oldCover;
  @override
  Future<LibraryCollectionsSnapshot> loadSnapshot() async =>
      LibraryCollectionsSnapshot(
        lovedRows: const [],
        favoriteArtistRows: const [],
        playlistTrackRows: const [],
        playlistRows: [
          {
            'id': 'existing',
            'name': 'Existing',
            'cover_image_path': oldCover,
            'created_at': '2026-01-01',
            'updated_at': '2026-01-01',
          },
        ],
      );
  @override
  Future<void> replaceAllFromBackup(Map<String, dynamic> json) async {
    if (fail) throw StateError('database rejected restore');
    saved = json;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  for (final fail in [false, true]) {
    test(
      'untrusted playlist ID cannot escape private covers; rollback=$fail',
      () async {
        final root = await Directory.systemTemp.createTemp('cover-safe-');
        addTearDown(() => root.delete(recursive: true));
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => root.path);
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        final coverDir = Directory(p.join(root.path, 'playlist_covers'));
        await coverDir.create();
        final old = File(p.join(coverDir.path, 'existing.jpg'));
        await old.writeAsString('old cover');
        final victim = File(p.join(root.path, 'victim.jpg'));
        await victim.writeAsString('untouched picture');
        final db = _Database()
          ..oldCover = old.path
          ..fail = fail;
        final outputs = <String>[];
        final container = ProviderContainer(
          overrides: [
            libraryCollectionsProvider.overrideWith(
              () => LibraryCollectionsNotifier(
                database: db,
                probeCover: (_) async => (width: 100, height: 100),
                resizeCover:
                    ({
                      required inputPath,
                      required outputPath,
                      required maxDimension,
                    }) async {
                      outputs.add(outputPath);
                      expect(p.isWithin(coverDir.path, outputPath), isTrue);
                      await File(
                        outputPath,
                      ).writeAsBytes(await File(inputPath).readAsBytes());
                      return true;
                    },
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(libraryCollectionsProvider.notifier);
        final attack = '../victim';
        final operation = notifier.restoreFromBackup(
          {
            'playlists': [
              {'id': attack, 'name': 'Imported', 'tracks': <Object?>[]},
            ],
          },
          coverImages: {
            attack: {
              'data': base64Encode(utf8.encode('new cover')),
              'ext': '../../evil.jpg',
            },
          },
        );
        if (fail) {
          await expectLater(operation, throwsStateError);
        } else {
          await operation;
        }
        expect(await victim.readAsString(), 'untouched picture');
        expect(outputs, hasLength(1));
        if (fail) {
          expect(await old.readAsString(), 'old cover');
        } else {
          final path =
              ((db.saved['playlists'] as List).single as Map)['coverImagePath']
                  as String;
          expect(p.isWithin(coverDir.path, path), isTrue);
          expect(await File(path).readAsString(), 'new cover');
        }
      },
    );
  }
}
