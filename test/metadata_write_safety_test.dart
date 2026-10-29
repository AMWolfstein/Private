import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/ffmpeg/ffmpeg_metadata.dart';
import 'package:sistrum/services/ffmpeg/ffmpeg_replaygain.dart';
import 'package:sistrum/services/library/metadata_cover_resources.dart';
import 'package:sistrum/services/library/metadata_persistence_service.dart';
import 'package:sistrum/services/native/media_file_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.amwolfstein.sistrum/backend');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'preserving MP3 and M4A edits refuse an unsafe remux fallback',
    () async {
      final directory = await Directory.systemTemp.createTemp('tag-preserve-');
      addTearDown(() => directory.delete(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            fail('Preserving fallback invoked platform method ${call.method}');
          });
      final covers = MetadataCoverResources();
      addTearDown(covers.dispose);
      final m4a = File('${directory.path}/song.m4a');
      final mp3 = File('${directory.path}/song.mp3');
      final original = [1, 2, 3, 4, 5];
      await m4a.writeAsBytes(original);
      await mp3.writeAsBytes(original);

      for (final path in [m4a.path, mp3.path]) {
        final service = MetadataPersistenceService(
          covers: covers,
          edit: (_, _) async => {'success': true, 'method': 'ffmpeg'},
          read: (_) async => {},
        );
        final result = await service.save(
          MetadataSaveRequest(filePath: path, metadata: const {'title': 'new'}),
        );
        expect(result.failure, MetadataSaveFailure.ffmpeg);
        expect(result.error, isA<FFmpegMetadataFailure>());
      }
      expect(await m4a.readAsBytes(), original);
      expect(await mp3.readAsBytes(), original);
      expect(await directory.list().length, 2);
    },
  );

  test('M4A/MP4 ReplayGain never uses the lossy stream-copy fallback', () {
    for (final path in [
      'track.m4a',
      'track.MP4',
      'track.m4b',
      'track.opus',
      'track.ogg',
    ]) {
      expect(FFmpegReplayGain.requiresNativeWriter(path), isTrue, reason: path);
    }
    expect(FFmpegReplayGain.requiresNativeWriter('track.mp3'), isFalse);
    expect(FFmpegReplayGain.requiresNativeWriter('track.flac'), isFalse);
  });

  test('SAF write-back reports a retained recovery copy', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'writeTempToSaf');
          return jsonEncode({
            'success': false,
            'error': 'Provider stored an incomplete file',
            'recovery_path': '/cache/recovery/song.mp3',
          });
        });
    final result = await MediaFileBridge.writeTempToSafDetailed(
      '/tmp/song.mp3',
      'content://library/song.mp3',
    );
    expect(result.success, isFalse);
    expect(result.error, 'Provider stored an incomplete file');
    expect(result.recoveryPath, '/cache/recovery/song.mp3');
  });
}
