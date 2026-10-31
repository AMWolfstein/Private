import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/playback/audio/audio_route_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.amwolfstein.sistrum/audio_route');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('a route map is found', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.arguments, {'path': '/music/a.flac'});
      return <String, dynamic>{'platform': 'android', 'sdk': 34};
    });
    final read = await readAudioRouteInfo(path: '/music/a.flac');
    expect(read, isA<AudioRouteFound>());
    expect((read as AudioRouteFound).info.platform, 'android');
  });

  test('a null route is reported as not available, not as a failure', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    expect(await readAudioRouteInfo(), isA<AudioRouteNotAvailable>());
  });

  test('no platform implementation is not available', () async {
    expect(await readAudioRouteInfo(), isA<AudioRouteNotAvailable>());
  });

  test('a failing call is reported as a failure', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'route_error');
    });
    expect(await readAudioRouteInfo(), isA<AudioRouteReadFailed>());
  });
}
