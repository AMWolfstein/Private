import 'package:sistrum/services/native/native_channel.dart';

/// Android foreground-service notifications for user-started work.
final class NativeBackgroundWork {
  NativeBackgroundWork._();

  /// Keeps user-started work of [kind] alive with the screen off through an
  /// Android foreground service. Returns whether the platform accepted it.
  static Future<bool> start(
    String kind, {
    required String title,
    String text = '',
  }) async {
    final started = await nativeBackendChannel.invokeMethod<bool>(
      'startBackgroundWork',
      {'kind': kind, 'title': title, 'text': text},
    );
    return started ?? false;
  }

  /// Updates the Android work notification; [progress] is a percentage, or
  /// negative while indeterminate.
  static Future<void> update(
    String kind, {
    required String title,
    String text = '',
    int progress = -1,
  }) async {
    await nativeBackendChannel.invokeMethod('updateBackgroundWork', {
      'kind': kind,
      'title': title,
      'text': text,
      'progress': progress,
    });
  }

  static Future<void> stop(String kind) async {
    await nativeBackendChannel.invokeMethod('stopBackgroundWork', {
      'kind': kind,
    });
  }
}
