import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sistrum/services/playback/core/music_playback_deck.dart';

Uint8List wav(double hz) {
  const rate = 44100, samples = rate * 2;
  final data = ByteData(44 + samples * 2);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, data.lengthInBytes - 8, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    data.setInt16(
      44 + i * 2,
      (sin(2 * pi * hz * i / rate) * 8192).round(),
      Endian.little,
    );
  }
  return data.buffer.asUint8List();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android starts the next deck without a Dart resume command', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('native-gapless-');
    final outgoing = MusicPlaybackDeck(playerId: 'gapless-integration-a');
    final incoming = MusicPlaybackDeck(playerId: 'gapless-integration-b');
    try {
      final first = await File('${root.path}/first.wav').writeAsBytes(wav(440));
      final next = await File('${root.path}/next.wav').writeAsBytes(wav(660));
      for (final deck in [outgoing, incoming]) {
        await deck.setReleaseMode(ReleaseMode.stop);
        await deck.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              audioFocus: AndroidAudioFocus.none,
            ),
          ),
        );
      }
      await outgoing.setSource(DeviceFileSource(first.path));
      await incoming.setSource(DeviceFileSource(next.path));
      await outgoing.setNextDeck(incoming);
      final completed = outgoing.onPlayerComplete.first;
      await outgoing.resume();
      await completed.timeout(const Duration(seconds: 6));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        await incoming.getCurrentPosition(),
        greaterThan(const Duration(milliseconds: 20)),
      );
      // This verifies native handoff, not a measured acoustic silence duration.
    } finally {
      await outgoing.setNextDeck(null);
      await outgoing.dispose();
      await incoming.dispose();
      await root.delete(recursive: true);
    }
  }, skip: !Platform.isAndroid);
}
