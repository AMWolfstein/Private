import 'package:flutter/services.dart';

/// The native USB PCM channel that every deck shares. One event stream feeds
/// all decks, and every request takes a ticket from one sequence, so a deck
/// accepts only the events carrying its own ticket.
class UsbPcmBridge {
  UsbPcmBridge({MethodChannel? channel, EventChannel? events})
    : channel =
          channel ?? const MethodChannel('com.amwolfstein.sistrum/usb_pcm'),
      _events =
          events ??
          const EventChannel('com.amwolfstein.sistrum/usb_pcm/events');

  final MethodChannel channel;
  final EventChannel _events;
  Stream<dynamic>? _stream;
  int _tickets = 0;

  /// The one native event stream, created on first use.
  Stream<dynamic> get events => _stream ??= _events.receiveBroadcastStream();

  /// A ticket unique across every deck that shares this bridge.
  int nextTicket() => ++_tickets;
}

/// The bridge the app's decks share.
final usbPcmBridge = UsbPcmBridge();
