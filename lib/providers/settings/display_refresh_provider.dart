import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/services/display/display_refresh_rate.dart';

/// The native controller, or null where there is none (host tests, non-Android).
final displayRefreshChannelProvider = Provider<DisplayRefreshRateChannel?>(
  (ref) => Platform.isAndroid ? DisplayRefreshRateChannel() : null,
);

/// Android's latest display report. Watching it keeps the saved preference
/// applied: every change of the setting is sent to the native controller,
/// which requests the rate while the app is in front.
final displayRefreshProvider =
    NotifierProvider<DisplayRefreshNotifier, DisplayRefreshState>(
      DisplayRefreshNotifier.new,
    );

class DisplayRefreshNotifier extends Notifier<DisplayRefreshState> {
  /// The rate being sent, so a push that arrives meanwhile does not send again.
  int? _sending;

  @override
  DisplayRefreshState build() {
    final channel = ref.watch(displayRefreshChannelProvider);
    if (channel == null) return DisplayRefreshState.unavailable;

    channel.setStateHandler((pushed) {
      state = pushed;
      // A new native controller (the Activity added it after Dart started)
      // holds no preference yet. Sending the saved one is a single call: once
      // the native side holds it, its pushes match and nothing is sent again.
      final saved = ref.read(settingsProvider).displayRefreshRate;
      if (pushed.attached && pushed.preferenceHz != saved) {
        unawaited(_send(channel, saved));
      }
    });
    ref.onDispose(() => channel.setStateHandler(null));

    // Sends the saved choice now and each time it changes. A refused request
    // is not retried; the native side keeps it until the choice changes.
    ref.listen<int>(
      settingsProvider.select((s) => s.displayRefreshRate),
      (_, hz) => unawaited(_send(channel, hz)),
      fireImmediately: true,
    );
    return DisplayRefreshState.unavailable;
  }

  Future<void> _send(DisplayRefreshRateChannel channel, int hz) async {
    if (_sending == hz) return;
    _sending = hz;
    try {
      final result = await channel.setPreference(hz);
      if (!ref.mounted) return;
      state = result;
    } finally {
      if (_sending == hz) _sending = null;
    }
  }
}
