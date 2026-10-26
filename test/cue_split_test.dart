import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/l10n/app_localizations.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/services/ffmpeg_cue.dart';
import 'package:spotiflac_android/services/ffmpeg_models.dart';
import 'package:spotiflac_android/services/library_database_models.dart';
import 'package:spotiflac_android/widgets/local_song_file_actions.dart';

class _ScanLibrary extends LocalLibraryNotifier {
  _ScanLibrary(this.initialSources);

  final List<LocalLibrarySource> initialSources;
  final scanned = <String>[];

  @override
  LocalLibraryState build() => LocalLibraryState(sources: initialSources);

  @override
  Future<void> startSourceScan(
    String sourceId, {
    bool forceFullScan = false,
  }) async {
    scanned.add(sourceId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cue_split_test_');
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  CueSplitTrackInfo track(int number, String title, double start) =>
      CueSplitTrackInfo(
        number: number,
        title: title,
        artist: 'Artist',
        startSec: start,
        endSec: start + 10,
      );

  group('CUE split export', () {
    test('a failed cover embed does not abort the other tracks', () async {
      final paths = [
        '${directory.path}/01 - First.flac',
        '${directory.path}/02 - Second.flac',
      ];
      for (final path in paths) {
        await File(path).writeAsBytes([1]);
      }
      final embedded = <String>[];
      final created = <String>[];
      final exported = await exportCueSplitOutputs(
        paths,
        tree: 'content://library',
        coverPath: '${directory.path}/cover.jpg',
        embedCover: (path, cover) async {
          embedded.add(path);
          if (path.endsWith('01 - First.flac')) {
            throw StateError('native cover failure');
          }
        },
        createFile: (path) async {
          created.add(path);
          return 'content://library/${path.split(Platform.pathSeparator).last}';
        },
      );

      expect(exported, 2);
      expect(embedded, paths);
      expect(created, paths);
    });

    test('only files the export layer created count as saved', () async {
      final paths = [
        '${directory.path}/01 - First.flac',
        '${directory.path}/02 - Second.flac',
      ];
      final exported = await exportCueSplitOutputs(
        paths,
        tree: 'content://library',
        createFile: (path) async =>
            path.endsWith('01 - First.flac') ? null : 'content://library/02',
      );

      expect(exported, 1);
      expect(cueSplitFailureCount(0, paths.length, exported), 1);
    });

    test('a rejected copy does not abort the remaining tracks', () async {
      final paths = [
        '${directory.path}/01 - First.flac',
        '${directory.path}/02 - Second.flac',
        '${directory.path}/03 - Third.flac',
      ];
      final attempted = <String>[];
      final exported = await exportCueSplitOutputs(
        paths,
        tree: 'content://library',
        createFile: (path) async {
          attempted.add(path);
          if (path.endsWith('01 - First.flac')) {
            throw StateError('destination revoked');
          }
          return 'content://library/${path.split(Platform.pathSeparator).last}';
        },
      );

      expect(exported, 2);
      expect(attempted, paths);
      expect(cueSplitFailureCount(0, paths.length, exported), 1);
    });
  });

  group('CUE split result', () {
    late AppLocalizations l10n;
    setUpAll(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
    });

    test('counts outputs the export layer could not create', () {
      expect(cueSplitFailureCount(0, 3, 2), 1);
      expect(cueSplitFailureCount(1, 3, 3), 1);
      expect(cueSplitFailureCount(null, 0, 0), 0);
    });

    test('reports partial, complete and outside-library results', () {
      expect(
        cueSplitResultMessage(l10n, 2, 1, true),
        l10n.cueSplitPartialSuccess(2, 1),
      );
      expect(
        cueSplitResultMessage(l10n, 2, 1, false),
        '${l10n.cueSplitPartialSuccess(2, 1)}\n'
        '${l10n.cueSplitSavedOutsideLibrary}',
      );
      expect(cueSplitResultMessage(l10n, 3, 0, true), l10n.cueSplitSuccess(3));
      expect(cueSplitResultMessage(l10n, 0, 2, false), l10n.cueSplitFailed);
    });

    test('matches the exact and nested destination folders', () {
      const sources = [
        LocalLibrarySource(id: 'music', path: '/music', displayName: 'Music'),
        LocalLibrarySource(
          id: 'saf',
          path: 'content://tree/library',
          displayName: 'Library',
        ),
      ];

      expect(cueSplitDestinationSource(sources, '/music')?.id, 'music');
      expect(cueSplitDestinationSource(sources, '/music/Albums')?.id, 'music');
      expect(
        cueSplitDestinationSource(
          sources,
          'content://tree/library%2FAlbums',
        )?.id,
        'saf',
      );
      expect(cueSplitDestinationSource(sources, '/music2'), isNull);
      expect(cueSplitDestinationSource(sources, 'content://other'), isNull);
    });

    test('matches SAF trees against filesystem-path sources', () {
      const sources = [
        LocalLibrarySource(
          id: 'fs',
          path: '/storage/emulated/0/Music',
          displayName: 'Music',
        ),
      ];

      expect(
        cueSplitDestinationSource(
          sources,
          'content://com.android.externalstorage.documents/tree/primary%3AMusic',
        )?.id,
        'fs',
      );
      expect(
        cueSplitDestinationSource(
          sources,
          'content://com.android.externalstorage.documents/tree/'
          'primary%3AMusic%2FAlbums',
        )?.id,
        'fs',
      );
      expect(
        cueSplitDestinationSource(
          sources,
          'content://com.android.externalstorage.documents/tree/primary%3AMusic2',
        ),
        isNull,
      );
    });

    test('matches a removable-volume SAF tree to a path source', () {
      const sources = [
        LocalLibrarySource(
          id: 'sd',
          path: '/storage/1A2B-3C4D/Music',
          displayName: 'SD card',
        ),
      ];

      expect(
        cueSplitDestinationSource(
          sources,
          'content://com.android.externalstorage.documents/tree/'
          '1A2B-3C4D%3AMusic',
        )?.id,
        'sd',
      );
      expect(
        cueSplitDestinationSource(
          sources,
          'content://com.android.externalstorage.documents/tree/'
          '1A2B-3C4D%3AMusic%2FAlbums',
        )?.id,
        'sd',
      );
      expect(
        cueSplitDestinationSource(
          sources,
          'content://com.android.externalstorage.documents/tree/'
          '1A2B-3C4D%3AMusic2',
        ),
        isNull,
      );
      expect(
        cueSplitDestinationSource(
          sources,
          'content://com.android.externalstorage.documents/tree/'
          'FFFF-0000%3AMusic',
        ),
        isNull,
      );
      expect(
        cueSplitDestinationSource(
          sources,
          'content://com.android.externalstorage.documents/tree/'
          'primary%3AMusic',
        ),
        isNull,
      );
    });

    test('matches a removable-volume root source', () {
      const sources = [
        LocalLibrarySource(
          id: 'sd-root',
          path: '/storage/1A2B-3C4D',
          displayName: 'SD card',
        ),
      ];

      expect(
        cueSplitDestinationSource(
          sources,
          'content://com.android.externalstorage.documents/tree/1A2B-3C4D%3A',
        )?.id,
        'sd-root',
      );
      expect(
        cueSplitDestinationSource(
          sources,
          'content://com.android.externalstorage.documents/tree/'
          '1A2B-3C4D%3AMusic',
        )?.id,
        'sd-root',
      );
      expect(
        cueSplitDestinationSource(
          sources,
          'content://com.android.externalstorage.documents/tree/'
          'FFFF-0000%3AMusic',
        ),
        isNull,
      );
    });

    test('a split inside a library folder rescans only available sources', () {
      const sources = [
        LocalLibrarySource(id: 'music', path: '/music', displayName: 'Music'),
        LocalLibrarySource(
          id: 'offline',
          path: '/offline',
          displayName: 'Offline',
          available: false,
        ),
      ];
      final library = _ScanLibrary(sources);
      final container = ProviderContainer(
        overrides: [localLibraryProvider.overrideWith(() => library)],
      );
      addTearDown(container.dispose);

      expect(
        cueSplitHandleDestination(container, '/music/Albums', exported: 3),
        isTrue,
      );
      expect(library.scanned, ['music']);

      // Still inside the library, but an unavailable source must not scan.
      expect(
        cueSplitHandleDestination(container, '/offline', exported: 1),
        isTrue,
      );
      expect(library.scanned, ['music']);

      expect(
        cueSplitHandleDestination(container, 'content://other', exported: 1),
        isFalse,
      );
      expect(
        cueSplitHandleDestination(container, '/music', exported: 0),
        isFalse,
      );
      expect(library.scanned, ['music']);
    });
  });

  group('CUE track extraction', () {
    test('a failed track is cleaned up and counted', () async {
      final result = await FFmpegCue.splitCueToTracks(
        audioPath: '${directory.path}/album.flac',
        outputDir: directory.path,
        tracks: [track(1, 'First', 0), track(2, 'Second', 10)],
        albumMetadata: const {},
        execute: (arguments) async {
          final output = arguments[arguments.length - 2];
          await File(output).writeAsBytes([1, 2, 3]);
          final failed = output.contains('01 - First');
          return FFmpegResult(
            success: !failed,
            returnCode: failed ? 1 : 0,
            output: failed ? 'invalid stream' : '',
          );
        },
      );

      expect(result, isNotNull);
      expect(result!.failed, 1);
      expect(result.paths, hasLength(1));
      expect(result.paths.single, contains('02 - Second'));
      expect(File('${directory.path}/01 - First.flac').existsSync(), isFalse);
      expect(File('${directory.path}/02 - Second.flac').existsSync(), isTrue);
    });

    test('a split where every track fails reports the failures', () async {
      final result = await FFmpegCue.splitCueToTracks(
        audioPath: '${directory.path}/album.flac',
        outputDir: directory.path,
        tracks: [track(1, 'First', 0)],
        albumMetadata: const {},
        execute: (arguments) async {
          final output = arguments[arguments.length - 2];
          await File(output).writeAsBytes([1, 2, 3]);
          return FFmpegResult(success: false, returnCode: 1, output: 'failed');
        },
      );

      expect(result, isNotNull);
      expect(result!.paths, isEmpty);
      expect(result.failed, 1);
      expect(File('${directory.path}/01 - First.flac').existsSync(), isFalse);
    });

    test(
      're-encoding seeks before the input and keeps the track length',
      () async {
        final commands = <List<String>>[];
        final result = await FFmpegCue.splitCueToTracks(
          audioPath: '${directory.path}/album.flac',
          outputDir: directory.path,
          tracks: [
            CueSplitTrackInfo(
              number: 1,
              title: 'First',
              artist: '',
              startSec: 0,
              endSec: 10,
            ),
            CueSplitTrackInfo(
              number: 2,
              title: 'Second',
              artist: '',
              startSec: 90.5,
              endSec: 190.5,
            ),
          ],
          albumMetadata: const {},
          execute: (arguments) async {
            commands.add(List.of(arguments));
            final output = arguments[arguments.length - 2];
            await File(output).writeAsBytes([1, 2, 3]);
            return FFmpegResult(success: true, returnCode: 0, output: '');
          },
        );

        expect(result, isNotNull);
        expect(commands, hasLength(2));
        final second = commands[1];
        // Input seeking: the decoder starts at the track boundary.
        expect(second.indexOf('-ss'), lessThan(second.indexOf('-i')));
        expect(second.sublist(second.indexOf('-ss'), second.indexOf('-i')), [
          '-ss',
          '00:01:30.500',
        ]);
        // `-t` is the track length, not the absolute end of the sheet.
        expect(second[second.indexOf('-t') + 1], '00:01:40.000');
        expect(second, isNot(contains('-to')));
        final codecIndex = second.indexOf('-c:a');
        expect(second.sublist(codecIndex, codecIndex + 4), [
          '-c:a',
          'flac',
          '-compression_level',
          '8',
        ]);
      },
    );

    test(
      'stream copy keeps output seeking for its packet boundaries',
      () async {
        final commands = <List<String>>[];
        final result = await FFmpegCue.splitCueToTracks(
          audioPath: '${directory.path}/album.mp3',
          outputDir: directory.path,
          tracks: [track(1, 'First', 90.5)],
          albumMetadata: const {},
          execute: (arguments) async {
            commands.add(List.of(arguments));
            final output = arguments[arguments.length - 2];
            await File(output).writeAsBytes([1, 2, 3]);
            return FFmpegResult(success: true, returnCode: 0, output: '');
          },
        );

        expect(result, isNotNull);
        final arguments = commands.single;
        expect(arguments.indexOf('-i'), lessThan(arguments.indexOf('-ss')));
        expect(arguments[arguments.indexOf('-to') + 1], '00:01:40.500');
        expect(arguments, containsAllInOrder(['-c:a', 'copy']));
      },
    );

    test('duplicate track names never share an output file', () async {
      final result = await FFmpegCue.splitCueToTracks(
        audioPath: '${directory.path}/album.flac',
        outputDir: directory.path,
        tracks: [track(1, 'Same', 0), track(1, 'Same', 10)],
        albumMetadata: const {},
        execute: (arguments) async {
          final output = arguments[arguments.length - 2];
          await File(output).writeAsBytes([1, 2, 3]);
          final failed = output.contains('(2)');
          return FFmpegResult(
            success: !failed,
            returnCode: failed ? 1 : 0,
            output: '',
          );
        },
      );

      expect(result, isNotNull);
      expect(result!.failed, 1);
      expect(result.paths.single, contains('01 - Same.flac'));
      expect(File('${directory.path}/01 - Same.flac').existsSync(), isTrue);
      expect(
        File('${directory.path}/01 - Same (2).flac').existsSync(),
        isFalse,
      );
    });
  });
}
