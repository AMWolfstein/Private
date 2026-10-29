import 'package:sistrum/utils/log_redaction.dart';

class LogEntry {
  final DateTime timestamp;
  final String level;
  final String tag;
  final String message;
  final String? error;
  final bool isFromGo;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.isFromGo = false,
  });

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  String get previewMessage => truncateLogText(message);

  String? get previewError => error == null ? null : truncateLogText(error!);

  @override
  String toString() {
    final errorPart = error != null ? ' | $error' : '';
    final nativePart = isFromGo ? ' [Native]' : '';
    return '[$formattedTime] [$level]$nativePart [$tag] $message$errorPart';
  }
}

String formatLogEntries(Iterable<LogEntry> entries) {
  return entries.map((entry) => entry.toString()).join('\n');
}

const logExportPrivacyNotice =
    'Logs may include local file paths, folder names and content URIs. Review before sharing.';
