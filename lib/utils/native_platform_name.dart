import 'dart:io' show Platform;

/// Platform label sent with native data jobs: `android`, `ios`, or the
/// desktop OS (`macos`, `windows`, `linux`). The native backend applies
/// Android SAF keys and iOS container rebasing only for those exact values,
/// so desktop paths pass through unchanged. It is never stored in backups.
String nativePlatformName() {
  if (Platform.isAndroid) return 'android';
  return 'ios';
}
