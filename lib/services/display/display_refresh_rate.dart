import 'package:flutter/services.dart';

/// What Android reports about the display, next to the app's request.
///
/// Every value comes from Android's `Display` APIs. They say which mode
/// Android reports as active; they do not prove the panel's real presentation
/// cadence, and they say nothing about how often Flutter produces frames.
class DisplayRefreshState {
  const DisplayRefreshState({
    required this.attached,
    required this.preferenceHz,
    required this.requestedModeId,
    required this.requestedHz,
    required this.activeModeId,
    required this.activeModeHz,
    required this.displayRefreshHz,
    required this.activeWidth,
    required this.activeHeight,
    required this.supportedRates,
    required this.modes,
    required this.settled,
    required this.powerSaveMode,
    required this.requestCount,
    required this.modeChangeCount,
  });

  /// No platform answer (tests, or the channel is not registered).
  static const unavailable = DisplayRefreshState(
    attached: false,
    preferenceHz: 0,
    requestedModeId: 0,
    requestedHz: 0,
    activeModeId: 0,
    activeModeHz: 0,
    displayRefreshHz: 0,
    activeWidth: 0,
    activeHeight: 0,
    supportedRates: [],
    modes: [],
    settled: true,
    powerSaveMode: false,
    requestCount: 0,
    modeChangeCount: 0,
  );

  factory DisplayRefreshState.fromMap(Map<Object?, Object?> map) {
    int i(String key) => (map[key] as num?)?.toInt() ?? 0;
    double d(String key) => (map[key] as num?)?.toDouble() ?? 0;
    return DisplayRefreshState(
      attached: map['attached'] == true,
      preferenceHz: i('preferenceHz'),
      requestedModeId: i('requestedModeId'),
      requestedHz: d('requestedHz'),
      activeModeId: i('activeModeId'),
      activeModeHz: d('activeModeHz'),
      displayRefreshHz: d('displayRefreshHz'),
      activeWidth: i('activeWidth'),
      activeHeight: i('activeHeight'),
      supportedRates: [
        for (final r in (map['supportedRates'] as List?) ?? const [])
          if (r is num) r.toInt(),
      ],
      modes: [
        for (final m in (map['modes'] as List?) ?? const [])
          if (m is String) m,
      ],
      settled: map['settled'] != false,
      powerSaveMode: map['powerSaveMode'] == true,
      requestCount: i('requestCount'),
      modeChangeCount: i('modeChangeCount'),
    );
  }

  /// An Activity and display were available when Android answered.
  final bool attached;

  /// The preference the native side holds, whole Hz; 0 is System Default.
  final int preferenceHz;

  /// The window's `preferredDisplayModeId`; 0 means no request.
  final int requestedModeId;

  /// Refresh rate of the requested mode, or 0 without a request.
  final double requestedHz;

  /// `Display.getMode()`: the mode Android reports as active.
  final int activeModeId;
  final double activeModeHz;

  /// `Display.getRefreshRate()`. Can differ from the mode's rate when Android
  /// lowers the app's frame rate without switching modes.
  final double displayRefreshHz;
  final int activeWidth;
  final int activeHeight;

  /// Whole-number rates of the modes at the current resolution, ascending.
  final List<int> supportedRates;

  /// Every supported mode as `id:WxH@Hz`, for diagnostics.
  final List<String> modes;

  /// False for a short time after the request changed, while Android may
  /// still be switching modes.
  final bool settled;

  /// Battery saver was on. Android often caps the refresh rate then, but this
  /// alone does not prove it refused the request.
  final bool powerSaveMode;

  /// Times the window request was actually written, since the engine started.
  final int requestCount;

  /// Active-mode changes Android reported while this Activity was visible.
  final int modeChangeCount;
}

/// How the app's request compares with what Android reports.
enum DisplayRefreshStatus {
  /// No preference: Android decides.
  systemDefault,

  /// The request was just made; Android may still be switching.
  requested,

  /// Android reports an active mode at the requested rate.
  active,

  /// Android reports another rate after the request had time to apply.
  notApplied,

  /// The display has no mode at this rate and the current resolution.
  unsupported,

  /// Android gave no display information (no Activity or no platform).
  unavailable,
}

/// Status of [preferenceHz] against [state]. "Active" needs Android's
/// reported mode to match; a request alone never counts.
DisplayRefreshStatus displayRefreshStatus(
  int preferenceHz,
  DisplayRefreshState state,
) {
  if (preferenceHz <= 0) return DisplayRefreshStatus.systemDefault;
  if (!state.attached) return DisplayRefreshStatus.unavailable;
  if (!state.supportedRates.contains(preferenceHz)) {
    return DisplayRefreshStatus.unsupported;
  }
  // The native side may not have the preference yet.
  if (state.preferenceHz != preferenceHz) return DisplayRefreshStatus.requested;
  if ((state.activeModeHz - preferenceHz).abs() <= 1) {
    return DisplayRefreshStatus.active;
  }
  return state.settled
      ? DisplayRefreshStatus.notApplied
      : DisplayRefreshStatus.requested;
}

/// Typed access to the native refresh-rate controller.
class DisplayRefreshRateChannel {
  DisplayRefreshRateChannel({MethodChannel? methods})
    : _methods = methods ?? const MethodChannel(methodChannelName);

  static const methodChannelName = 'com.amwolfstein.sistrum/display_refresh';

  final MethodChannel _methods;

  Future<DisplayRefreshState> getState() => _call('getState');

  /// Sends the preference; 0 clears the app's request.
  Future<DisplayRefreshState> setPreference(int hz) =>
      _call('setPreference', {'hz': hz < 0 ? 0 : hz});

  /// Receives the state each time it changes on the native side (a display
  /// report, an Activity attaching). Null stops receiving.
  ///
  /// A push rather than a stream: the native controller exists only once an
  /// Activity has added it, and a push needs no subscription made before then.
  void setStateHandler(void Function(DisplayRefreshState state)? onState) {
    _methods.setMethodCallHandler(
      onState == null
          ? null
          : (call) async {
              final args = call.arguments;
              if (call.method == 'onState' && args is Map) {
                onState(DisplayRefreshState.fromMap(args));
              }
            },
    );
  }

  Future<DisplayRefreshState> _call(String method, [Object? args]) async {
    try {
      final result = await _methods.invokeMapMethod<Object?, Object?>(
        method,
        args,
      );
      return result == null
          ? DisplayRefreshState.unavailable
          : DisplayRefreshState.fromMap(result);
    } on MissingPluginException {
      return DisplayRefreshState.unavailable;
    } on PlatformException {
      return DisplayRefreshState.unavailable;
    }
  }
}

/// Where a nominal refresh rate came from.
enum DisplayRefreshSource {
  /// `Display.getMode()`: the mode Android reports as active.
  androidActiveMode,

  /// The engine's display refresh rate, as the Dart side sees it.
  flutterReported,

  /// Neither source had a usable value; [nominalDisplayRefresh] used the fallback.
  fallback,
}

/// The nominal refresh rate a benchmark budget is computed from.
typedef DisplayRefreshReference = ({double hz, DisplayRefreshSource source});

/// Rate used when Android and Flutter both give nothing usable.
const double kDisplayRefreshFallbackHz = 60;

/// The nominal rate for frame budgets: Android's active mode first.
///
/// Flutter's value is not used while Android has an active mode. The engine
/// refreshes its display snapshot only with display metrics (size, density),
/// not on a refresh-only mode change, so the Dart value can stay at a rate
/// the panel has left (the 90 Hz read on a 120 Hz panel).
DisplayRefreshReference nominalDisplayRefresh({
  required DisplayRefreshState android,
  required double? flutterHz,
}) {
  if (android.attached && android.activeModeHz > 0) {
    return (
      hz: android.activeModeHz,
      source: DisplayRefreshSource.androidActiveMode,
    );
  }
  if (flutterHz != null && flutterHz > 0) {
    return (hz: flutterHz, source: DisplayRefreshSource.flutterReported);
  }
  return (hz: kDisplayRefreshFallbackHz, source: DisplayRefreshSource.fallback);
}

/// Whether Flutter's value differs from Android's active mode by more than
/// 1 Hz. Null when either value is missing.
bool? displayRefreshDisagrees({
  required DisplayRefreshState android,
  required double? flutterHz,
}) {
  if (!android.attached || android.activeModeHz <= 0) return null;
  if (flutterHz == null || flutterHz <= 0) return null;
  return (android.activeModeHz - flutterHz).abs() > 1;
}
