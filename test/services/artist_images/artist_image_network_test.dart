import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/artist_images/artist_image_network.dart';

void main() {
  test('Wi-Fi only allows Wi-Fi and nothing else', () {
    const policy = ArtistImageNetwork.wifi;
    expect(policy.allows(ArtistNetworkKind.wifi), isTrue);
    expect(policy.allows(ArtistNetworkKind.cellular), isFalse);
    expect(policy.allows(ArtistNetworkKind.other), isFalse);
    expect(policy.allows(ArtistNetworkKind.none), isFalse);
  });

  test('mobile data only allows cellular', () {
    const policy = ArtistImageNetwork.mobile;
    expect(policy.allows(ArtistNetworkKind.cellular), isTrue);
    expect(policy.allows(ArtistNetworkKind.wifi), isFalse);
    expect(policy.allows(ArtistNetworkKind.none), isFalse);
  });

  test('both allows Wi-Fi and cellular, never other or none', () {
    const policy = ArtistImageNetwork.both;
    expect(policy.allows(ArtistNetworkKind.wifi), isTrue);
    expect(policy.allows(ArtistNetworkKind.cellular), isTrue);
    expect(policy.allows(ArtistNetworkKind.other), isFalse);
    expect(policy.allows(ArtistNetworkKind.none), isFalse);
  });

  test('unknown or missing stored values fall back to Wi-Fi only', () {
    expect(ArtistImageNetwork.fromStored(null), ArtistImageNetwork.wifi);
    expect(ArtistImageNetwork.fromStored('ethernet'), ArtistImageNetwork.wifi);
    expect(ArtistImageNetwork.fromStored('mobile'), ArtistImageNetwork.mobile);
    expect(ArtistImageNetwork.fromStored('both'), ArtistImageNetwork.both);
  });

  test('an unreadable network state counts as no network', () async {
    const channel = MethodChannel('com.amwolfstein.sistrum/backend');
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'boom');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    expect(await readArtistNetworkKind(), ArtistNetworkKind.none);
  });

  test('the native answer is read into the network kind', () async {
    const channel = MethodChannel('com.amwolfstein.sistrum/backend');
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getNetworkKind');
          return 'cellular';
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    expect(await readArtistNetworkKind(), ArtistNetworkKind.cellular);
  });
}
