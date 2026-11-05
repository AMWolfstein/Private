import 'package:sistrum/services/display/display_refresh_rate.dart';

/// Records Android-reported display-mode changes during a benchmark. Bounded,
/// and fed only by the native controller's change events, never per frame.
class GlassDisplayModeLog {
  GlassDisplayModeLog({this.capacity = 32});

  final int capacity;
  final List<String> _entries = [];
  final Stopwatch _clock = Stopwatch();
  int _changes = 0;
  int? _lastModeId;
  double? _lastHz;
  bool _active = false;

  /// Starts a fresh log at the benchmark start, with the mode at that moment.
  void begin(DisplayRefreshState state) {
    _entries.clear();
    _changes = 0;
    _clock
      ..reset()
      ..start();
    _active = true;
    _lastModeId = state.activeModeId;
    _lastHz = state.activeModeHz;
    _record('start', state);
  }

  /// Stops recording; the entries stay for the report.
  void end() {
    _active = false;
    _clock.stop();
  }

  /// Notes [state] when the active mode or its rate changed. [context] names
  /// what the benchmark was doing (phase, renderer, surfaces).
  void onState(DisplayRefreshState state, String context) {
    if (!_active) return;
    if (state.activeModeId == _lastModeId && state.activeModeHz == _lastHz) {
      return;
    }
    _lastModeId = state.activeModeId;
    _lastHz = state.activeModeHz;
    _changes++;
    _record(context, state);
  }

  int get changes => _changes;
  List<String> get entries => List.unmodifiable(_entries);

  void _record(String context, DisplayRefreshState state) {
    if (_entries.length >= capacity) return;
    final t = _clock.elapsedMilliseconds / 1000;
    _entries.add(
      't=${t.toStringAsFixed(1)}s $context '
      'active_mode=${state.activeModeId}@${state.activeModeHz.toStringAsFixed(2)}Hz '
      'display_refresh=${state.displayRefreshHz.toStringAsFixed(2)}Hz',
    );
  }
}

/// Report lines for the display request and Android's reported mode. These
/// are Android-reported values: they are not the measured presentation
/// cadence, and FrameTiming says nothing about it either.
List<String> glassDisplayRefreshLines({
  required int preferenceHz,
  required DisplayRefreshState state,
  GlassDisplayModeLog? log,
}) {
  String hz(double v) => v.toStringAsFixed(2);
  final status = displayRefreshStatus(preferenceHz, state);
  return [
    'display_refresh_selected=${preferenceHz == 0 ? 'system_default' : '${preferenceHz}Hz'}',
    'display_refresh_requested='
        '${state.requestedModeId == 0 ? 'none' : 'mode ${state.requestedModeId} @ ${hz(state.requestedHz)}Hz'}',
    'display_active_mode[android]='
        '${state.attached ? 'mode ${state.activeModeId} ${state.activeWidth}x${state.activeHeight} @ ${hz(state.activeModeHz)}Hz' : 'unavailable'}',
    'display_get_refresh_rate_hz[android]=${state.attached ? hz(state.displayRefreshHz) : 'unavailable'}',
    'display_refresh_status=${status.name}',
    'display_power_save_mode=${state.powerSaveMode}',
    'display_supported_modes=${state.modes.isEmpty ? 'unavailable' : state.modes.join(', ')}',
    if (log != null) ...[
      'display_mode_changes_during_benchmark=${log.changes}',
      for (final e in log.entries) '  display_mode: $e',
    ],
    'display_note=Android-reported request and mode only; not the panel\'s '
        'presentation cadence. Confirm with dumpsys SurfaceFlinger --latency.',
  ];
}
