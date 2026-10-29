import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sistrum/utils/best_effort_delete.dart';
import 'package:sistrum/utils/logger.dart';

/// The one method channel into the native backend.
const nativeBackendChannel = MethodChannel('com.amwolfstein.sistrum/backend');

const _jsonResultFileKey = '__json_file';
const _backgroundJsonDecodeThresholdBytes = 128 * 1024;

Object? nativeDecodeJsonInBackground(String json) => jsonDecode(json);

Object? nativeDecodeJsonFileInBackground(String path) {
  final contents = File(path).readAsStringSync();
  return contents.isEmpty ? null : jsonDecode(contents);
}

Future<Map<String, dynamic>> nativeInvokeMap(
  String method, [
  dynamic args,
]) async {
  final result = await nativeBackendChannel.invokeMethod(method, args);
  return nativeDecodeRequiredMapResultAsync(result, method);
}

Object? nativeDecodeJsonResult(dynamic result) {
  if (result is String) {
    if (result.isEmpty) return null;
    return jsonDecode(result);
  }
  return result;
}

Future<Object?> nativeDecodeJsonResultAsync(dynamic result) async {
  if (result is Map && result[_jsonResultFileKey] is String) {
    final file = File(result[_jsonResultFileKey] as String);
    try {
      // Read and decode where the result is built, so the UI isolate never
      // retains a second copy of the entire spill file's text.
      return await compute(nativeDecodeJsonFileInBackground, file.path);
    } finally {
      await deleteBestEffort(file);
    }
  }
  if (result is String &&
      result.length >= _backgroundJsonDecodeThresholdBytes) {
    return nativeDecodeJsonStringAsync(result);
  }
  return nativeDecodeJsonResult(result);
}

Future<Object?> nativeDecodeJsonStringAsync(String json) {
  if (json.length < _backgroundJsonDecodeThresholdBytes) {
    return Future<Object?>.value(jsonDecode(json));
  }
  return compute(nativeDecodeJsonInBackground, json);
}

Map<String, dynamic>? nativeDecodeNullableMapResult(
  dynamic result,
  String method,
) {
  final decoded = nativeDecodeJsonResult(result);
  if (decoded == null) return null;
  if (decoded is Map) {
    return decoded.cast<String, dynamic>();
  }
  throw FormatException(
    'Expected nullable map result from $method, got ${decoded.runtimeType}',
  );
}

Future<Map<String, dynamic>> nativeDecodeRequiredMapResultAsync(
  dynamic result,
  String method,
) async {
  final decoded = await nativeDecodeJsonResultAsync(result);
  if (decoded is Map) {
    return decoded.cast<String, dynamic>();
  }
  throw FormatException(
    'Expected map result from $method, got ${decoded.runtimeType}',
  );
}

Map<String, dynamic> nativeDecodeMapResult(dynamic result) {
  if (result is Map) {
    return result.cast<String, dynamic>();
  }
  if (result is String) {
    if (result.isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(result);
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
  }
  return const <String, dynamic>{};
}

/// Native notifications on the backend channel. The channel holds a single
/// handler, so it is installed once, on first use.
final class NativeBackendEvents {
  NativeBackendEvents._();

  static final _libraryStorageChanges = StreamController<void>.broadcast();
  static bool _handlerInstalled = false;

  static Stream<void> libraryStorageChanges() {
    ensureInstalled();
    return _libraryStorageChanges.stream;
  }

  /// Installs the backend channel handler once; later calls do nothing.
  static void ensureInstalled() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    nativeBackendChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'libraryScanError':
          final args = call.arguments;
          if (args is Map) {
            final path = args['path']?.toString() ?? '';
            final operation = args['operation']?.toString() ?? 'scan';
            final message = args['message']?.toString() ?? 'Unknown error';
            AppLogger('LocalLibrary').e('$operation [$path]: $message');
          }
          return null;
        case 'libraryStorageChanged':
          _libraryStorageChanges.add(null);
          return null;
        default:
          return null;
      }
    });
  }
}
