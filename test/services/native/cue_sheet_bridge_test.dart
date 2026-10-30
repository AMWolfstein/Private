import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/native/cue_sheet_bridge.dart';
import 'package:sistrum/services/native/native_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a CUE sheet is parsed by the native backend with its folder', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodCall? seen;
    messenger.setMockMethodCallHandler(nativeBackendChannel, (call) async {
      seen = call;
      return {
        'tracks': [
          {'title': 'First'},
        ],
      };
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(nativeBackendChannel, null),
    );

    final result = await CueSheetBridge.parseCueSheet(
      '/music/album.cue',
      audioDir: '/music',
    );

    expect(seen?.method, 'parseCueSheet');
    expect(seen?.arguments, {
      'cue_path': '/music/album.cue',
      'audio_dir': '/music',
    });
    expect(result['tracks'], [
      {'title': 'First'},
    ]);
  });
}
