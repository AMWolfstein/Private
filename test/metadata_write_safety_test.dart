import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/services/ffmpeg_metadata.dart';
import 'package:spotiflac_android/services/ffmpeg_replaygain.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.zarz.spotiflac/backend');

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
      final file = File('${directory.path}/song.m4a');
      final original = [1, 2, 3, 4, 5];
      await file.writeAsBytes(original);
      expect(
        await FFmpegMetadata.embedMetadataToM4a(
          m4aPath: file.path,
          metadata: const {'TITLE': 'new'},
        ),
        isNull,
      );
      expect(
        await FFmpegMetadata.embedMetadataToMp3(
          mp3Path: file.path,
          preserveMetadata: true,
          metadata: const {'TITLE': 'new'},
        ),
        isNull,
      );
      expect(await file.readAsBytes(), original);
      expect(await directory.list().length, 1);
    },
  );

  test('MP3 tag edits stream-copy audio and never re-encode', () {
    final arguments = FFmpegMetadata.buildMp3EmbedArguments(
      mp3Path: '/music/song.mp3',
      tempOutput: '/tmp/out.mp3',
      metadata: const {'TITLE': 'Song'},
      preserveMetadata: true,
    );
    expect(arguments, containsAllInOrder(['-c:a', 'copy']));
    expect(arguments, isNot(contains('libmp3lame')));
    expect(arguments, isNot(contains('-b:a')));
  });

  test(
    'M4A freeform failure is reported before the file is promoted',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'acquireMediaDirectory') return 'scope';
            if (call.method == 'releaseMediaDirectory') return null;
            expect(call.method, 'writeM4AFreeformTags');
            return jsonEncode({'error': 'atom write failed'});
          });
      expect(
        await FFmpegMetadata.writeM4AFreeformTags('/tmp/song.m4a', const {
          'ISRC': 'US1234567890',
        }),
        isFalse,
      );
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
    final result = await PlatformBridge.writeTempToSafDetailed(
      '/tmp/song.mp3',
      'content://library/song.mp3',
    );
    expect(result.success, isFalse);
    expect(result.error, 'Provider stored an incomplete file');
    expect(result.recoveryPath, '/cache/recovery/song.mp3');
  });
}
