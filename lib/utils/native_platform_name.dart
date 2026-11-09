import 'dart:io' show Platform;

String nativePlatformName() {
  if (Platform.isAndroid) return 'android';
  return 'ios';
}
