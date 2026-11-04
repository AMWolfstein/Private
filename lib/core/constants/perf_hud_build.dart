import 'package:flutter/foundation.dart';

/// Build-time gate for the developer performance HUD and Developer Options.
///
/// Enabled by `--dart-define=SISTRUM_PERF_HUD=true` (profile or release
/// builds used for measurement) and always in debug builds. Ordinary release
/// builds without the define keep the HUD and its unlock path out of reach.
const bool kPerfHudBuildAllowed =
    bool.fromEnvironment('SISTRUM_PERF_HUD') || kDebugMode;
