import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sistrum/services/native/native_channel.dart';

String _encodeJsonInBackground(Object? value) => jsonEncode(value);

class _NativeDataJobState {
  bool dispatched = false;
  bool cancelled = false;
}

class InstallationState {
  final bool markerExisted;
  final bool markerCreated;
  final bool freshPackageInstall;

  const InstallationState({
    required this.markerExisted,
    required this.markerCreated,
    required this.freshPackageInstall,
  });

  const InstallationState.unsupported()
    : markerExisted = true,
      markerCreated = true,
      freshPackageInstall = false;

  factory InstallationState.fromMap(Map<String, dynamic> map) {
    return InstallationState(
      markerExisted: map['marker_existed'] == true,
      markerCreated: map['marker_created'] == true,
      freshPackageInstall: map['fresh_package_install'] == true,
    );
  }
}

bool shouldResetRestoredInstallation({
  required bool hasPersistedSettings,
  required InstallationState installState,
}) {
  return hasPersistedSettings &&
      !installState.markerExisted &&
      installState.markerCreated &&
      installState.freshPackageInstall;
}

class PlatformBridge {
  static int _nativeDataJobSerial = 0;
  static final _nativeDataJobs = <String, Set<_NativeDataJobState>>{};

  static bool get supportsCoreBackend => Platform.isAndroid;

  /// A single background native operation. Binary inputs never become base64
  /// JSON, and large request/result codecs stay off the UI isolate.
  static Future<Map<String, dynamic>> runNativeDataJob(
    Map<String, dynamic> request, {
    Uint8List? bytes,
    String? requestId,
  }) async {
    final id =
        requestId ??
        'data_${DateTime.now().microsecondsSinceEpoch}_${_nativeDataJobSerial++}';
    final state = _NativeDataJobState();
    final states = _nativeDataJobs.putIfAbsent(id, () => {});
    states.add(state);
    try {
      final encoded = await compute(_encodeJsonInBackground, request);
      if (state.cancelled) {
        throw PlatformException(
          code: 'CANCELLED',
          message: 'Native data job cancelled',
        );
      }
      state.dispatched = true;
      Object? result;
      try {
        result = await nativeBackendChannel.invokeMethod('runNativeDataJob', {
          'request_json': encoded,
          'request_id': id,
          'bytes': ?bytes,
        });
      } finally {
        state.dispatched = false;
      }
      return await nativeDecodeRequiredMapResultAsync(
        result,
        'runNativeDataJob',
      );
    } finally {
      states.remove(state);
      if (states.isEmpty) _nativeDataJobs.remove(id);
    }
  }

  static Future<void> cancelNativeDataJob(String requestId) async {
    final states = _nativeDataJobs[requestId];
    if (states == null) return;
    for (final state in states) {
      state.cancelled = true;
    }
    if (states.any((state) => state.dispatched)) {
      await nativeBackendChannel.invokeMethod<void>('cancelNativeDataJob', {
        'request_id': requestId,
      });
    }
  }

  static Future<void> setScreenAwake(bool enabled) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await nativeBackendChannel.invokeMethod<void>('setScreenAwake', {
      'enabled': enabled,
    });
  }

  static Future<InstallationState> ensureInstallMarker() async {
    if (!Platform.isAndroid) return const InstallationState.unsupported();
    final result = await nativeInvokeMap('ensureInstallMarker');
    return InstallationState.fromMap(result);
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

  /// Keeps user-started work of [kind] alive with the screen off through an
  /// Android foreground service. Returns whether the platform accepted it.
  static Future<bool> startBackgroundWork(
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
  static Future<void> updateBackgroundWork(
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

  static Future<void> stopBackgroundWork(String kind) async {
    await nativeBackendChannel.invokeMethod('stopBackgroundWork', {
      'kind': kind,
    });
  }

  static Future<void> releaseNativeMemory({bool underPressure = false}) async {
    try {
      await nativeBackendChannel.invokeMethod(
        underPressure ? 'releaseMemoryUnderPressure' : 'releaseMemory',
      );
    } catch (_) {}
  }
}
