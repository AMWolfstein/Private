import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/ffmpeg/ffmpeg_models.dart';
import 'package:sistrum/services/playback/audio/replaygain_service.dart';
import 'package:sistrum/services/playback/audio/replaygain_write_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.amwolfstein.sistrum/backend');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late List<String> copies;
  late Map<String, dynamic> metadata;
  var copyCount = 0, edits = 0, publications = 0;
  String? refusedUri;
  var allowPublish = true;

  setUp(() async {
    ReplayGainService.integrityChecks = false;
    directory = await Directory.systemTemp.createTemp('replaygain-combined-');
    copies = [];
    metadata = {'audio_codec': 'flac'};
    copyCount = edits = publications = 0;
    refusedUri = null;
    allowPublish = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setLoggingEnabled') return null;
      if (call.method == 'acquireMediaDirectory') return '';
      if (call.method == 'releaseMediaDirectory') return null;
      final args = Map<String, dynamic>.from(call.arguments as Map);
      switch (call.method) {
        case 'safCopyToTemp':
          if (args['uri'] == refusedUri) {
            throw PlatformException(code: 'saf_permission_denied');
          }
          final path = '${directory.path}/${copyCount++}.flac';
          await File(path).writeAsString('audio');
          copies.add(path);
          return path;
        case 'editFileMetadata':
          edits++;
          metadata.addAll(
            Map<String, dynamic>.from(
              jsonDecode(args['metadata_json'] as String) as Map,
            ),
          );
          return jsonEncode({'success': true, 'method': 'native_flac'});
        case 'readFileMetadata':
          return jsonEncode(metadata);
        case 'writeTempToSaf':
          publications++;
          return jsonEncode({'success': allowPublish});
        default:
          throw StateError('Unexpected method ${call.method}');
      }
    });
  });
  tearDown(() async {
    ReplayGainService.integrityChecks = true;
    messenger.setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  const fields = {
    'replaygain_track_gain': '-2.00 dB',
    'replaygain_track_peak': '0.8',
    'replaygain_album_gain': '-3.00 dB',
    'replaygain_album_peak': '0.9',
  };
  test(
    'combined SAF tags require one native edit and one publication',
    () async {
      final result = await ReplayGainService.writeTags(
        'content://music/a',
        fields,
      );
      expect(result.isWritten, isTrue);
      expect(edits, 1);
      expect(publications, 1);
      expect(metadata, containsPair('replaygain_track_gain', '-2.00 dB'));
      expect(metadata, containsPair('replaygain_album_gain', '-3.00 dB'));
      expect(copies, hasLength(1));
      expect(await File(copies.single).exists(), isFalse);
    },
  );
  test('denied guard prevents an edit and cleans the SAF copy', () async {
    final result = await ReplayGainService.writeTags(
      'content://music/a',
      fields,
      mayWrite: () async => false,
    );
    expect(result.failure, ReplayGainWriteFailure.deferred);
    expect(edits, 0);
    expect(publications, 0);
    expect(await File(copies.single).exists(), isFalse);
  });
  test('playback beginning after the edit prevents SAF publication', () async {
    var checks = 0;
    final result = await ReplayGainService.writeTags(
      'content://music/a',
      fields,
      mayWrite: () async => ++checks == 1,
    );
    expect(result.failure, ReplayGainWriteFailure.deferred);
    expect(edits, 1);
    expect(publications, 0);
    expect(await File(copies.single).exists(), isFalse);
  });
  test(
    'SAF publication failures remain failures, with no temporary files retained',
    () async {
      allowPublish = false;
      final result = await ReplayGainService.writeTags(
        'content://music/a',
        fields,
      );
      expect(result.failure, ReplayGainWriteFailure.storageFailed);
      expect(await File(copies.single).exists(), isFalse);
    },
  );
  test(
    'mixed album measurements receive real paths and keep copies until scanning ends',
    () async {
      final local = await File(
        '${directory.path}/local.flac',
      ).writeAsString('local audio');
      await ReplayGainService.measureAlbum(
        [local.path, 'content://music/a', 'content://music/b'],
        scan: (paths) async {
          expect(paths.first, local.path);
          expect(paths, hasLength(3));
          expect(paths.any((path) => path.startsWith('content://')), isFalse);
          for (final path in paths) {
            expect(await File(path).exists(), isTrue);
          }
          return const ReplayGainResult(
            trackGain: '-3 dB',
            trackPeak: '0.9',
            integratedLufs: -15,
            truePeakLinear: 0.9,
          );
        },
      );
      for (final path in copies) {
        expect(await File(path).exists(), isFalse);
      }
      expect(await local.readAsString(), 'local audio');
    },
  );
  test(
    'a refused album member cleans earlier copies and never scans a partial album',
    () async {
      refusedUri = 'content://music/refused';
      var scans = 0;
      await expectLater(
        ReplayGainService.measureAlbum(
          ['content://music/a', refusedUri!],
          scan: (_) async {
            scans++;
            return null;
          },
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(scans, 0);
      for (final path in copies) {
        expect(await File(path).exists(), isFalse);
      }
    },
  );
  test('a throwing album scanner also releases its SAF copies', () async {
    await expectLater(
      ReplayGainService.measureAlbum([
        'content://music/a',
      ], scan: (_) async => throw StateError('decoder failed')),
      throwsStateError,
    );
    expect(await File(copies.single).exists(), isFalse);
  });
  test(
    'empty gains cannot be used as an internal ReplayGain removal operation',
    () async {
      final result = await ReplayGainService.writeTags('content://music/a', {
        'replaygain_track_gain': '',
        'replaygain_track_peak': '',
        'replaygain_album_gain': '',
        'replaygain_album_peak': '',
      });
      expect(result.failure, ReplayGainWriteFailure.verificationFailed);
      expect(edits, 0);
      expect(publications, 0);
    },
  );
}
