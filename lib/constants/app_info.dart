import 'package:flutter/foundation.dart';

class AppInfo {
  static const String version = '5.1.1';
  static const String buildNumber = '168';

  static const String gitCommit = String.fromEnvironment('GIT_COMMIT');
  static String get shortGitCommit =>
      gitCommit.length > 8 ? gitCommit.substring(0, 8) : gitCommit;

  static String get displayVersion => kDebugMode ? 'Internal' : version;

  static const String appName = 'Sistrum';
  static const String copyright = '© 2026 \u005a\u0061\u0072\u007a Eleutherius';
}
