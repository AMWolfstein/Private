import 'package:flutter/services.dart';
import 'package:sistrum/services/native/native_channel.dart';

/// The network the device is using right now, as reported by Android.
enum ArtistNetworkKind {
  wifi,
  cellular,

  /// Ethernet, VPN or another transport. Never used for automatic downloads.
  other,

  /// No connected network, or the state could not be read.
  none;

  static ArtistNetworkKind parse(String? value) => switch (value) {
    'wifi' => wifi,
    'cellular' => cellular,
    'other' => other,
    _ => none,
  };
}

/// Which networks automatic artist image downloads may use.
enum ArtistImageNetwork {
  wifi,
  mobile,
  both;

  /// The stored name; unknown values fall back to Wi-Fi only.
  static ArtistImageNetwork fromStored(String? value) => switch (value) {
    'mobile' => mobile,
    'both' => both,
    _ => wifi,
  };

  bool allows(ArtistNetworkKind kind) => switch (this) {
    wifi => kind == ArtistNetworkKind.wifi,
    mobile => kind == ArtistNetworkKind.cellular,
    both =>
      kind == ArtistNetworkKind.wifi || kind == ArtistNetworkKind.cellular,
  };
}

/// Reads the active network kind from Android. A failed call counts as no
/// network, so an automatic download never starts on a state it cannot read.
Future<ArtistNetworkKind> readArtistNetworkKind() async {
  try {
    final value = await nativeBackendChannel.invokeMethod<String>(
      'getNetworkKind',
    );
    return ArtistNetworkKind.parse(value);
  } on PlatformException {
    return ArtistNetworkKind.none;
  } on MissingPluginException {
    return ArtistNetworkKind.none;
  }
}
