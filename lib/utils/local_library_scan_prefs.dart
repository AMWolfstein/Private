import 'package:shared_preferences/shared_preferences.dart';

const localLibraryLastScannedAtKey = 'local_library_last_scanned_at';
const localLibraryActiveScanSourceKey = 'local_library_active_scan_source';
const localLibraryActiveScanStartedAtKey =
    'local_library_active_scan_started_at';
const localLibraryRecoveredScanKey = 'local_library_recovered_scan';

DateTime? readLocalLibraryLastScannedAt(SharedPreferences prefs) {
  final raw = prefs.get(localLibraryLastScannedAtKey);
  if (raw is String) {
    return DateTime.tryParse(raw);
  }

  // Backward compatibility for older builds that may have stored epoch millis.
  if (raw is int) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    } on ArgumentError {
      return null;
    }
  }

  return null;
}

Future<void> writeLocalLibraryLastScannedAt(
  SharedPreferences prefs,
  DateTime value,
) {
  return prefs.setString(localLibraryLastScannedAtKey, value.toIso8601String());
}

Future<void> clearLocalLibraryLastScannedAt(SharedPreferences prefs) {
  return prefs.remove(localLibraryLastScannedAtKey);
}
