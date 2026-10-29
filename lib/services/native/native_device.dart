import 'package:flutter/foundation.dart';
import 'package:sistrum/services/native/native_channel.dart';

/// Device-level calls: screen wake lock, app exit, backend identity and memory.
final class NativeDevice {
  NativeDevice._();

  static Future<void> setScreenAwake(bool enabled) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await nativeBackendChannel.invokeMethod<void>('setScreenAwake', {
      'enabled': enabled,
    });
  }

  static Future<void> exitApp() async {
    await nativeBackendChannel.invokeMethod('exitApp');
  }

  static Future<Map<String, String>> getBackendImplementations({
    String? filePath,
  }) async {
    final result = await nativeBackendChannel.invokeMapMethod<String, String>(
      'getBackendImplementations',
      filePath == null ? null : {'file_path': filePath},
    );
    return result ?? const {};
  }

  static Future<void> releaseMemory({bool underPressure = false}) async {
    try {
      await nativeBackendChannel.invokeMethod(
        underPressure ? 'releaseMemoryUnderPressure' : 'releaseMemory',
      );
    } catch (_) {}
  }
}
