import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sistrum/l10n/l10n.dart';

/// Uses the system's real audio routes and keeps native discovery in native UI.
class AudioOutputButton extends StatefulWidget {
  const AudioOutputButton({super.key, this.color, this.onPickerChanged});

  final Color? color;
  final ValueChanged<bool>? onPickerChanged;

  @override
  State<AudioOutputButton> createState() => _AudioOutputButtonState();
}

class _AudioOutputButtonState extends State<AudioOutputButton> {
  static const _androidChannel = MethodChannel(
    'com.amwolfstein.sistrum/audio_output',
  );
  bool _opening = false;

  Future<void> _showAndroidPicker() async {
    if (_opening) return;
    _opening = true;
    widget.onPickerChanged?.call(true);
    var opened = false;
    try {
      opened = await _androidChannel.invokeMethod<bool>('show') ?? false;
    } on PlatformException {
      // Show a visible failure instead of leaving an unresponsive control.
    } on MissingPluginException {
      // The native bridge is not available on unsupported builds.
    } finally {
      _opening = false;
      if (mounted) widget.onPickerChanged?.call(false);
    }
    if (mounted && !opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.nowPlayingAudioOutputUnavailable)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return IconButton(
          tooltip: context.l10n.nowPlayingAudioOutput,
          color: widget.color,
          icon: const Icon(Icons.speaker_group_outlined),
          onPressed: _showAndroidPicker,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
