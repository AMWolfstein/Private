import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/widgets/player/artwork/player_artwork.dart';

void main() {
  testWidgets('a legacy remote artwork URL falls back to the placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PlayerArtwork(
          artUri: 'https://example.com/legacy-cover.jpg',
          colorScheme: ColorScheme.dark(),
        ),
      ),
    );
    expect(find.byIcon(Icons.music_note), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  test('playable media keeps a legacy remote cover out of playback state', () {
    final item = LocalLibraryItem(
      id: 'one',
      filePath: '/one.flac',
      trackName: 'One',
      artistName: 'Artist',
      albumName: 'Album',
      coverPath: 'https://example.com/legacy-cover.jpg',
      scannedAt: DateTime.utc(2026),
    );
    expect(playableFromLocal(item).artUri, isNull);

    final local = LocalLibraryItem(
      id: 'two',
      filePath: '/two.flac',
      trackName: 'Two',
      artistName: 'Artist',
      albumName: 'Album',
      coverPath: '/covers/two.jpg',
      scannedAt: DateTime.utc(2026),
    );
    expect(playableFromLocal(local).artUri, 'file:///covers/two.jpg');
  });

  testWidgets(
    'track changes retain the decoded cover while the next image loads',
    (tester) async {
      final cache = PaintingBinding.instance.imageCache;
      addTearDown(() {
        cache.clear();
        cache.clearLiveImages();
      });
      Future<ui.Image> pixel(Color color) async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(color, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(1, 1);
        picture.dispose();
        return image;
      }

      final first = await tester.runAsync(() => pixel(Colors.red));
      final second = await tester.runAsync(() => pixel(Colors.blue));
      final pending = Completer<ImageInfo>();
      cache.putIfAbsent(
        FileImage(File('/cover-first.png')),
        () => OneFrameImageStreamCompleter(
          Future.value(ImageInfo(image: first!)),
        ),
      );
      cache.putIfAbsent(
        FileImage(File('/cover-second.png')),
        () => OneFrameImageStreamCompleter(pending.future),
      );
      Widget app(String path) => MaterialApp(
        home: PlayerArtwork(
          artUri: path,
          colorScheme: const ColorScheme.dark(),
        ),
      );
      await tester.pumpWidget(app('/cover-first.png'));
      await tester.pump();
      final displayed = tester.widget<RawImage>(find.byType(RawImage)).image;
      expect(displayed, isNotNull);
      await tester.pumpWidget(app('/cover-second.png'));
      expect(
        tester.widget<RawImage>(find.byType(RawImage)).image,
        same(displayed),
      );
      expect(find.byIcon(Icons.music_note), findsNothing);
      pending.complete(ImageInfo(image: second!));
      await tester.pumpAndSettle();
      expect(
        tester.widget<RawImage>(find.byType(RawImage)).image,
        isNot(same(displayed)),
      );
      expect(find.byIcon(Icons.music_note), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
