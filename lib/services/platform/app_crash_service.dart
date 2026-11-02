import 'package:flutter/services.dart';
import 'package:sistrum/utils/logging/log_entry.dart';
import 'package:sistrum/utils/logging/log_redaction.dart';
import 'package:sistrum/utils/logging/logger.dart';

/// Stores bounded context for a later confirmed process death, not a crash notice
/// for every handled Flutter error. The native reporter owns durable storage.
class AppCrashService {
  static const _channel = MethodChannel('com.amwolfstein.sistrum/backend');
  static Future<Map<String, dynamic>?> latest() =>
      _channel.invokeMapMethod<String, dynamic>('getLatestAppCrash');

  static Future<void> recordRuntimeError(
    Object error,
    StackTrace? stack,
  ) async {
    try {
      final entries = LogBuffer().entries;
      await _channel.invokeMethod<void>('recordAppRuntimeError', {
        'error': redactSensitiveText(error.toString()),
        'stack': redactSensitiveText(stack?.toString() ?? ''),
        'logs': formatLogEntries(
          entries.skip(entries.length > 40 ? entries.length - 40 : 0),
        ),
      });
    } catch (_) {
      // Reporting must never recursively trigger a global error handler.
    }
  }
}
