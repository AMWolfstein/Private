import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/utils/logging/logger.dart';

final _log = AppLogger('PerfHud');

const _enabledKey = 'perf_hud_enabled';
const _dxKey = 'perf_hud_dx';
const _dyKey = 'perf_hud_dy';
const _compactKey = 'perf_hud_compact';
const _opacityKey = 'perf_hud_opacity';
const _devUnlockedKey = 'developer_options_unlocked';

class PerfHudSettings {
  const PerfHudSettings({
    this.enabled = false,
    this.position,
    this.compact = true,
    this.opacity = 0.88,
    this.developerUnlocked = false,
  });

  final bool enabled;

  /// Last top-left corner in logical pixels, or null for the default corner.
  final ({double dx, double dy})? position;
  final bool compact;

  /// Panel opacity, clamped to 0.4–1.0.
  final double opacity;

  /// Set by seven taps on the About version row in a permitted build.
  final bool developerUnlocked;

  PerfHudSettings copyWith({
    bool? enabled,
    ({double dx, double dy})? position,
    bool? compact,
    double? opacity,
    bool? developerUnlocked,
  }) => PerfHudSettings(
    enabled: enabled ?? this.enabled,
    position: position ?? this.position,
    compact: compact ?? this.compact,
    opacity: opacity ?? this.opacity,
    developerUnlocked: developerUnlocked ?? this.developerUnlocked,
  );
}

/// Persists the HUD and Developer Options state. Reads and writes are best
/// effort: a failed write keeps the in-memory value for this session.
class PerfHudSettingsNotifier extends Notifier<PerfHudSettings> {
  @override
  PerfHudSettings build() {
    unawaited(_load());
    return const PerfHudSettings();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dx = prefs.getDouble(_dxKey);
      final dy = prefs.getDouble(_dyKey);
      state = PerfHudSettings(
        enabled: prefs.getBool(_enabledKey) ?? false,
        position: dx != null && dy != null ? (dx: dx, dy: dy) : null,
        compact: prefs.getBool(_compactKey) ?? true,
        opacity: _clampOpacity(prefs.getDouble(_opacityKey) ?? 0.88),
        developerUnlocked: prefs.getBool(_devUnlockedKey) ?? false,
      );
    } catch (error) {
      _log.e('Could not load the performance HUD settings: $error');
    }
  }

  Future<void> _write(void Function(SharedPreferences prefs) write) async {
    try {
      write(await SharedPreferences.getInstance());
    } catch (error) {
      _log.e('Could not save the performance HUD settings: $error');
    }
  }

  void setEnabled(bool value) {
    state = state.copyWith(enabled: value);
    unawaited(_write((prefs) => prefs.setBool(_enabledKey, value)));
  }

  void setPosition(double dx, double dy) {
    state = state.copyWith(position: (dx: dx, dy: dy));
    unawaited(
      _write((prefs) async {
        await prefs.setDouble(_dxKey, dx);
        await prefs.setDouble(_dyKey, dy);
      }),
    );
  }

  void setCompact(bool value) {
    state = state.copyWith(compact: value);
    unawaited(_write((prefs) => prefs.setBool(_compactKey, value)));
  }

  void setOpacity(double value) {
    final clamped = _clampOpacity(value);
    state = state.copyWith(opacity: clamped);
    unawaited(_write((prefs) => prefs.setDouble(_opacityKey, clamped)));
  }

  void unlockDeveloperOptions() {
    if (state.developerUnlocked) return;
    state = state.copyWith(developerUnlocked: true);
    unawaited(_write((prefs) => prefs.setBool(_devUnlockedKey, true)));
  }
}

double _clampOpacity(double value) => value.clamp(0.4, 1.0).toDouble();

final perfHudSettingsProvider =
    NotifierProvider<PerfHudSettingsNotifier, PerfHudSettings>(
      PerfHudSettingsNotifier.new,
    );
