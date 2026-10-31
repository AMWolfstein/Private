import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sistrum/services/native/native_channel.dart';

String _encodeJsonInBackground(Object? value) => jsonEncode(value);

/// Requests up to this many characters of text (counting every node) encode on
/// the calling isolate. Spawning an isolate costs more than encoding them.
const _inlineEncodeBudget = 64 * 1024;

class _NativeDataJobState {
  bool dispatched = false;
  bool cancelled = false;
}

/// Background native operations. Each running job is registered by request
/// id so [cancel] reaches it from any caller.
final class NativeDataJobs {
  NativeDataJobs._();

  static int _nativeDataJobSerial = 0;
  static final _nativeDataJobs = <String, Set<_NativeDataJobState>>{};

  /// A single background native operation. Binary inputs never become base64
  /// JSON, and large request/result codecs stay off the UI isolate.
  /// Jobs currently registered; each one leaves the map when it completes.
  @visibleForTesting
  static int get activeJobCount => _nativeDataJobs.length;

  static Future<Map<String, dynamic>> run(
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
      final encoded = isInlineEncodable(request)
          ? jsonEncode(request)
          : await compute(_encodeJsonInBackground, request);
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

  /// True when [value] is plain JSON data small enough to encode inline. Any
  /// other type, or anything over the budget, takes the isolate path so the
  /// encoder's own errors and large-payload behaviour are unchanged.
  @visibleForTesting
  static bool isInlineEncodable(Object? value) {
    var budget = _inlineEncodeBudget;
    bool fits(Object? node) {
      budget--;
      if (budget < 0) return false;
      if (node == null || node is bool || node is num) return true;
      if (node is String) {
        budget -= node.length;
        return budget >= 0;
      }
      if (node is List) {
        for (final item in node) {
          if (!fits(item)) return false;
        }
        return true;
      }
      if (node is Map) {
        for (final entry in node.entries) {
          if (entry.key is! String || !fits(entry.key) || !fits(entry.value)) {
            return false;
          }
        }
        return true;
      }
      return false;
    }

    return fits(value);
  }

  static Future<void> cancel(String requestId) async {
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
}
