import 'dart:async';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/utils/lyrics/lyric_models.dart';
import 'package:sistrum/widgets/player/lyrics/player_lyrics.dart';

part 'player_lyrics_repaint_1.dart';
part 'player_lyrics_repaint_2.dart';

const _text = 'AAAA BBBB';
const _lyrics = ParsedLyrics(
  synced: true,
  wordSynced: true,
  plainText: '',
  lines: [
    LyricLine(
      time: Duration.zero,
      end: Duration(seconds: 20),
      text: _text,
      words: [
        LyricWord(
          time: Duration.zero,
          end: Duration(seconds: 10),
          text: 'AAAA ',
        ),
        LyricWord(
          time: Duration(seconds: 10),
          end: Duration(seconds: 20),
          text: 'BBBB',
        ),
      ],
    ),
  ],
);

Finder get _paint => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == _text,
  ),
  matching: find.byType(CustomPaint),
);

List<List<Rect>> _segmentBoxes(WidgetTester tester) {
  // Inspect the existing painter payload without adding production test hooks.
  // ignore: avoid_dynamic_calls
  return (tester.widget<CustomPaint>(_paint).painter as dynamic).segmentBoxes
      as List<List<Rect>>;
}

Future<List<int>> _pixels(WidgetTester tester) async {
  final painter = tester.widget<CustomPaint>(_paint).painter!;
  final size = tester.getSize(_paint);
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.ceil(), size.height.ceil());
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final result = bytes.buffer.asUint8List().toList();
    image.dispose();
    picture.dispose();
    return result;
  }))!;
}

void main() {
  _registerPlayerLyricsRepaint1();
  _registerPlayerLyricsRepaint2();
}
