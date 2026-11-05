import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/services/display/display_refresh_rate.dart';

/// Android's answer for a 60/90/120 Hz panel at one resolution.
DisplayRefreshState state({
  int preferenceHz = 0,
  double activeHz = 60,
  bool settled = true,
  bool attached = true,
  List<int> rates = const [60, 90, 120],
}) => DisplayRefreshState.fromMap({
  'attached': attached,
  'preferenceHz': preferenceHz,
  'requestedModeId': preferenceHz == 0 ? 0 : 3,
  'requestedHz': preferenceHz.toDouble(),
  'activeModeId': 1,
  'activeModeHz': activeHz,
  'displayRefreshHz': activeHz,
  'activeWidth': 1080,
  'activeHeight': 2400,
  'supportedRates': rates,
  'modes': ['1:1080x2400@60.00', '2:1080x2400@90.00', '3:1080x2400@120.00'],
  'settled': settled,
  'powerSaveMode': false,
  'requestCount': 1,
  'modeChangeCount': 0,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('status', () {
    test('System Default is reported whatever the display does', () {
      expect(
        displayRefreshStatus(0, state(activeHz: 120)),
        DisplayRefreshStatus.systemDefault,
      );
    });

    for (final hz in [60, 90, 120]) {
      test('$hz Hz is active only when Android reports it', () {
        expect(
          displayRefreshStatus(hz, state(preferenceHz: hz, activeHz: hz + .0)),
          DisplayRefreshStatus.active,
        );
      });
    }

    test('a fractional active rate counts as its whole number', () {
      expect(
        displayRefreshStatus(60, state(preferenceHz: 60, activeHz: 59.94)),
        DisplayRefreshStatus.active,
      );
    });

    test('a refused request reads as not applied once settled', () {
      // Android kept 60 Hz although 120 Hz was requested.
      expect(
        displayRefreshStatus(120, state(preferenceHz: 120, settled: false)),
        DisplayRefreshStatus.requested,
      );
      expect(
        displayRefreshStatus(120, state(preferenceHz: 120)),
        DisplayRefreshStatus.notApplied,
      );
    });

    test('an unsupported rate is never reported as requested or active', () {
      expect(
        displayRefreshStatus(144, state(preferenceHz: 144, activeHz: 144)),
        DisplayRefreshStatus.unsupported,
      );
    });

    test('no display information is unavailable, not active', () {
      expect(
        displayRefreshStatus(120, DisplayRefreshState.unavailable),
        DisplayRefreshStatus.unavailable,
      );
    });

    test('a preference the native side has not received yet is pending', () {
      expect(
        displayRefreshStatus(90, state(preferenceHz: 120, activeHz: 90)),
        DisplayRefreshStatus.requested,
      );
    });
  });

  group('state map', () {
    test('reads every field and tolerates missing ones', () {
      final s = state(preferenceHz: 120, activeHz: 120);
      expect(s.supportedRates, [60, 90, 120]);
      expect(s.requestedModeId, 3);
      expect(s.activeWidth, 1080);
      expect(s.modes, hasLength(3));
      final empty = DisplayRefreshState.fromMap(const {});
      expect(empty.attached, isFalse);
      expect(empty.supportedRates, isEmpty);
      expect(empty.settled, isTrue);
    });
  });

  group('channel', () {
    const name = DisplayRefreshRateChannel.methodChannelName;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(
      () => messenger.setMockMethodCallHandler(const MethodChannel(name), null),
    );

    test('sends the preference and returns Android\'s state', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(const MethodChannel(name), (
        call,
      ) async {
        calls.add(call);
        return {'attached': true, 'preferenceHz': 120, 'activeModeHz': 60.0};
      });
      final result = await DisplayRefreshRateChannel().setPreference(120);
      expect(calls.single.method, 'setPreference');
      expect(calls.single.arguments, {'hz': 120});
      expect(result.preferenceHz, 120);
      expect(result.activeModeHz, 60);
      await DisplayRefreshRateChannel().setPreference(-5);
      expect(calls.last.arguments, {'hz': 0});
    });

    test('native pushes reach the state handler', () async {
      final channel = DisplayRefreshRateChannel();
      final received = <DisplayRefreshState>[];
      channel.setStateHandler(received.add);
      await messenger.handlePlatformMessage(
        name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onState', {'attached': true, 'activeModeHz': 90.0}),
        ),
        (_) {},
      );
      expect(received.single.activeModeHz, 90);
      channel.setStateHandler(null);
    });

    test('a missing platform reads as unavailable', () async {
      final result = await DisplayRefreshRateChannel().getState();
      expect(result.attached, isFalse);
    });
  });

  group('persistence', () {
    test('the choice round-trips and defaults to System Default', () {
      expect(const AppSettings().displayRefreshRate, 0);
      final saved = const AppSettings(displayRefreshRate: 120).toJson();
      expect(AppSettings.fromJson(saved).displayRefreshRate, 120);
      expect(AppSettings.fromJson(const {}).displayRefreshRate, 0);
    });

    test('implausible stored values read as System Default', () {
      for (final bad in [-60, 0, 5000, double.nan, 'fast', true]) {
        expect(displayRefreshRateFromJson(bad), 0, reason: '$bad');
      }
      expect(displayRefreshRateFromJson(89.6), 90);
    });
  });
}
