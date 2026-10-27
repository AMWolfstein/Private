import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const backendChannel = MethodChannel('com.amwolfstein.sistrum/backend');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backendChannel, null);
  });

  test('complete metadata forwards descriptor format hint', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backendChannel, (call) async {
          expect(call.method, 'readFileMetadata');
          expect(call.arguments, {
            'file_path': '/proc/self/fd/42',
            'display_name': 'Song.opus',
          });
          return jsonEncode({'replaygain_track_gain': '-6.00 dB'});
        });
    final result = await PlatformBridge.readFileMetadata(
      '/proc/self/fd/42',
      displayName: 'Song.opus',
    );
    expect(result['replaygain_track_gain'], '-6.00 dB');
  });
}
