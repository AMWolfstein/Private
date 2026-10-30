import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/playback/audio/usb_pcm_bridge.dart';

void main() {
  test('tickets are unique across every user of one bridge', () {
    final bridge = UsbPcmBridge();
    final first = bridge.nextTicket();
    final second = bridge.nextTicket();
    expect(second, first + 1);
    expect({first, second, bridge.nextTicket()}, hasLength(3));
  });

  test('the native event stream is created once and shared', () {
    final bridge = UsbPcmBridge(
      events: const EventChannel('test/usb_pcm_events'),
    );
    expect(identical(bridge.events, bridge.events), isTrue);
  });
}
