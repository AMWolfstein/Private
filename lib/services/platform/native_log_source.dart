import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:sistrum/utils/logging/log_entry.dart';

/// Logging transport is independent of the bridge whose calls it records.
class NativeLogSource {
  const NativeLogSource({
    MethodChannel channel = const MethodChannel(
      'com.amwolfstein.sistrum/backend',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<Map<String, dynamic>> getSince(int index) async {
    final result = await _channel.invokeMethod<Object?>('getLogsSince', {
      'index': index,
    });
    final decoded = result is String
        ? (result.isEmpty ? null : jsonDecode(result))
        : result;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw FormatException(
      'Expected map result from getLogsSince, got ${decoded.runtimeType}',
    );
  }

  /// Reads this process's own logcat output (`logcat -d --pid=<pid>`).
  Future<NativeLogcatResult> readAppLogcat() async {
    try {
      final text = await _channel.invokeMethod<String>('getAppLogcat');
      return NativeLogcatText(text ?? '');
    } on PlatformException catch (error) {
      return NativeLogcatUnavailable(error.message ?? error.code);
    } on MissingPluginException catch (error) {
      return NativeLogcatUnavailable(error.message ?? 'not implemented');
    }
  }

  Future<void> setLoggingEnabled(bool enabled) =>
      _channel.invokeMethod<void>('setLoggingEnabled', {'enabled': enabled});

  Future<void> clear() => _channel.invokeMethod<void>('clearLogs');
}

/// Outcome of reading the app's logcat. Native code returns empty text when
/// logcat fails, so [NativeLogcatUnavailable] covers only transport failures.
sealed class NativeLogcatResult {
  const NativeLogcatResult();
}

final class NativeLogcatText extends NativeLogcatResult {
  const NativeLogcatText(this.text);
  final String text;
}

final class NativeLogcatUnavailable extends NativeLogcatResult {
  const NativeLogcatUnavailable(this.reason);
  final String reason;
}

final RegExp _threadtimeLine = RegExp(
  r'^(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})\.(\d{3})\s+\d+\s+\d+\s+([VDIWEF]) (.*?): ?(.*)$',
);

/// Parses `logcat -v threadtime` output. Continuation lines join the previous
/// entry; a leading line with no header becomes an INFO entry tagged `logcat`.
List<LogEntry> parseAppLogcat(String text, {required DateTime now}) {
  final entries = <LogEntry>[];
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trimRight();
    if (line.isEmpty || line.startsWith('--------- beginning of')) continue;
    final match = _threadtimeLine.firstMatch(line);
    if (match == null) {
      if (entries.isEmpty) {
        entries.add(
          LogEntry(timestamp: now, level: 'INFO', tag: 'logcat', message: line),
        );
      } else {
        final last = entries.removeLast();
        entries.add(
          LogEntry(
            timestamp: last.timestamp,
            level: last.level,
            tag: last.tag,
            message: '${last.message}\n$line',
          ),
        );
      }
      continue;
    }
    final level = switch (match.group(7)!) {
      'E' => 'ERROR',
      'F' => 'FATAL',
      'W' => 'WARN',
      'I' => 'INFO',
      _ => 'DEBUG',
    };
    entries.add(
      LogEntry(
        timestamp: DateTime(
          now.year,
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
          int.parse(match.group(3)!),
          int.parse(match.group(4)!),
          int.parse(match.group(5)!),
          int.parse(match.group(6)!),
        ),
        level: level,
        tag: match.group(8)!.trim(),
        message: match.group(9)!,
      ),
    );
  }
  return entries;
}
