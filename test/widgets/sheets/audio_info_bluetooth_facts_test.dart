import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/services/playback/audio/audio_route_info.dart';
import 'package:sistrum/services/playback/core/music_playback_deck.dart';
import 'package:sistrum/widgets/sheets/audio_info_facts.dart';

void main() {
  for (final type in ['bluetooth', 'bluetooth_le', 'hearing_aid', 'usb']) {
    test('$type separates negotiated transport from Android PCM defaults', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final info = AudioRouteInfo.fromMap({
        'platform': 'android',
        'mixerSampleRate': 48000,
        'framesPerBuffer': 192,
        'device': {
          'type': type,
          'name': 'Output',
          'sampleRates': [48000],
          'bitDepths': [16],
          'mixer': {'sampleRate': 48000, 'bitDepth': 16},
        },
      });
      final facts = AudioInfoFacts(
        l10n: l10n,
        metadata: {'sample_rate': 44100, 'format': 'flac'},
        path: '/song.flac',
        fileSize: null,
        route: info,
        usb: const UsbAudioStatus(),
        processing: null,
        settings: const AppSettings(),
      ).sections().expand((s) => s.facts).toList();
      final values = {for (final f in facts) f.label: f.value};
      if (type == 'usb') {
        expect(values[l10n.audioInfoOutputRate], isNotNull);
        expect(values[l10n.audioInfoBluetoothFormat], isNull);
      } else {
        expect(info.bluetoothFormatUnreported, true);
        expect(
          values[l10n.audioInfoBluetoothFormat],
          l10n.audioInfoAndroidNotReported,
        );
        expect(values[l10n.audioInfoOutputRate], isNull);
        expect(values[l10n.audioInfoOutputFormat], isNull);
        expect(values[l10n.audioInfoSystemDefaultRate], isNotNull);
      }
    });
  }
}
