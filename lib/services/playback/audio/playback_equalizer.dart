import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:sistrum/core/models/equalizer_settings.dart';

/// Shared by every playback deck, including AutoMix's incoming/outgoing decks.
final playbackEqualizer = ValueNotifier<EqualizerSettings>(
  const EqualizerSettings(),
);

/// A native error is surfaced in the editor rather than claiming EQ is active.
final playbackEqualizerError = ValueNotifier<String?>(null);

final _errors = <String, String>{};

void reportEqualizerError(String playerId, String? error) {
  if (error == null) {
    _errors.remove(playerId);
  } else {
    _errors[playerId] = error;
  }
  playbackEqualizerError.value = _errors.isEmpty ? null : _errors.values.first;
}

const kPlaybackEqualizerStorageKey = 'playback_equalizer_v1';

EqualizerSettings decodePlaybackEqualizerSettings(Map<String, dynamic> data) =>
    EqualizerSettings.fromJson(
      Map<String, dynamic>.from(data['settings'] as Map),
    );

/// Startup reads the same settings before a UI provider exists. Invalid saved
/// data is a neutral EQ; no headless read rewrites user preferences.
EqualizerSettings loadBootstrapEqualizer(SharedPreferences prefs) {
  try {
    final raw = prefs.getString(kPlaybackEqualizerStorageKey);
    if (raw == null) return const EqualizerSettings();
    return decodePlaybackEqualizerSettings(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
  } catch (_) {
    return const EqualizerSettings();
  }
}
