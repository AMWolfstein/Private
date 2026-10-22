import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/constants/app_info.dart';

/// Where Auto glass settled after measuring this device's raster times.
/// Each step only ever lowers the device-class choice.
enum MornyeGlassAutoStep {
  /// Kept the device class (full glass where it allows it).
  full,

  /// Lite glass at the chosen clarity level.
  lite,

  /// Lite glass at Level 1 (plain blur).
  liteFrosted,
}

/// The persisted probe result. [build] ties it to one app build, so an
/// update measures again.
@immutable
class MornyeGlassAutoResult {
  const MornyeGlassAutoResult({
    required this.build,
    required this.step,
    required this.done,
    this.p90,
  });

  final String build;

  /// The step in use; while [done] is false, the step being measured next.
  final MornyeGlassAutoStep step;
  final bool done;

  /// p90 raster time of the last measured window, in milliseconds.
  final double? p90;

  Map<String, Object?> toJson() => {
    'build': build,
    'step': step.name,
    'done': done,
    'p90': ?p90,
  };

  static MornyeGlassAutoResult? fromJson(Object? json) {
    if (json is! Map) return null;
    final build = json['build'];
    final step = MornyeGlassAutoStep.values.asNameMap()[json['step']];
    final done = json['done'];
    final p90 = json['p90'];
    if (build is! String || step == null || done is! bool) return null;
    return MornyeGlassAutoResult(
      build: build,
      step: step,
      done: done,
      p90: p90 is num ? p90.toDouble() : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MornyeGlassAutoResult &&
      other.build == build &&
      other.step == step &&
      other.done == done &&
      other.p90 == p90;

  @override
  int get hashCode => Object.hash(build, step, done, p90);
}

/// Device-specific, so it lives outside the app settings and their backups.
const kGlassAutoProbeKey = 'mornye_glass_auto_probe';

/// This build: version, build number and, when known, the commit.
String mornyeGlassAutoBuild() {
  final commit = AppInfo.shortGitCommit;
  return '${AppInfo.version}+${AppInfo.buildNumber}'
      '${commit.isEmpty ? '' : '-$commit'}';
}

/// The saved result for [build]; a result from another build is stale.
MornyeGlassAutoResult? loadGlassAutoResult(
  SharedPreferences prefs, {
  required String build,
}) {
  final raw = prefs.getString(kGlassAutoProbeKey);
  if (raw == null) return null;
  try {
    final result = MornyeGlassAutoResult.fromJson(jsonDecode(raw));
    return result?.build == build ? result : null;
  } on FormatException {
    return null;
  }
}

Future<void> saveGlassAutoResult(MornyeGlassAutoResult? result) async {
  final prefs = await SharedPreferences.getInstance();
  if (result == null) {
    await prefs.remove(kGlassAutoProbeKey);
  } else {
    await prefs.setString(kGlassAutoProbeKey, jsonEncode(result.toJson()));
  }
}

/// Collects raster times of real frames and reports their p90 once a window
/// is full. Frames in the first [warmup] after the first one are skipped:
/// startup decoding and the step change itself are not normal use.
class MornyeGlassAutoSampler {
  MornyeGlassAutoSampler();

  static const warmup = Duration(seconds: 3);
  static const windowFrames = 180;

  /// Above this p90 raster time Auto steps down.
  static const thresholdMs = 14.0;

  final _raster = <double>[];
  int? _originMicros;

  int get frames => _raster.length;

  /// Adds one frame; returns the window's p90 when it is complete.
  double? add({required double rasterMs, required int vsyncMicros}) {
    final origin = _originMicros ??= vsyncMicros;
    if (vsyncMicros - origin < warmup.inMicroseconds) return null;
    _raster.add(rasterMs);
    if (_raster.length < windowFrames) return null;
    final sorted = [..._raster]..sort();
    return sorted[math.min(
      sorted.length - 1,
      (0.9 * sorted.length).ceil() - 1,
    )];
  }

  /// The step after measuring [current] at [p90], or null to keep it.
  static MornyeGlassAutoStep? stepDown(
    MornyeGlassAutoStep current,
    double p90,
  ) {
    if (p90 <= thresholdMs) return null;
    return switch (current) {
      MornyeGlassAutoStep.full => MornyeGlassAutoStep.lite,
      MornyeGlassAutoStep.lite => MornyeGlassAutoStep.liteFrosted,
      MornyeGlassAutoStep.liteFrosted => null,
    };
  }
}
