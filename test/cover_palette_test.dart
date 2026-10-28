import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/theme/cover_palette.dart';

void main() {
  testWidgets(
    'same-path cover replacement refreshes palette and decoded image',
    (tester) async {
      await tester.runAsync(() async {
        final directory = await Directory.systemTemp.createTemp(
          'palette-replace-',
        );
        final file = File('${directory.path}/cover.png');
        final cache = PaintingBinding.instance.imageCache;
        Future<void> write(Color color) async {
          final recorder = ui.PictureRecorder();
          Canvas(
            recorder,
          ).drawRect(const Rect.fromLTWH(0, 0, 32, 32), Paint()..color = color);
          final picture = recorder.endRecording();
          final image = await picture.toImage(32, 32);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          picture.dispose();
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        }

        try {
          await write(Colors.blue);
          final first = await CoverPalette.resolve(file.path, Brightness.light);
          expect(first, isNotNull);
          // The small source-key lookup may evict a file while Flutter still
          // retains its decoded image. A later edit must stay fresh too.
          for (var index = 0; index < 33; index++) {
            await CoverPalette.resolve(
              '${directory.path}/missing-$index.png',
              Brightness.light,
            );
          }
          expect(CoverPalette.peek(file.path, Brightness.light), isNull);
          await write(Colors.red);
          await file.setLastModified(
            DateTime.now().add(const Duration(seconds: 1)),
          );
          final second = await CoverPalette.resolve(
            file.path,
            Brightness.light,
          );
          expect(second, isNot(same(first)));
          expect(
            CoverPalette.peekAnalysis(file.path)?.dominant,
            Colors.red.toARGB32(),
          );
        } finally {
          cache.clear();
          cache.clearLiveImages();
          await directory.delete(recursive: true);
        }
      });
    },
  );

  testWidgets('palette requests share a small aspect-preserving decode', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('palette-test-');
      final cache = PaintingBinding.instance.imageCache;
      cache.clear();
      cache.clearLiveImages();
      try {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 512, 256),
          Paint()..color = Colors.blue,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(512, 256);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        final file = File('${directory.path}/cover.png');
        await file.writeAsBytes(bytes!.buffer.asUint8List());

        // Concurrent requests share one analysis (and one decode).
        expect(
          identical(
            CoverPalette.resolveAnalysis(file.path),
            CoverPalette.resolveAnalysis(file.path),
          ),
          isTrue,
        );
        final scheme = await CoverPalette.resolve(file.path, Brightness.light);
        expect(scheme, isNotNull);
        expect(
          CoverPalette.peekAnalysis(file.path)?.dominant,
          Colors.blue.toARGB32(),
        );
        // The original is 512 x 256. Its cached decode fits inside 112 x 112
        // while preserving the 2:1 aspect ratio, instead of retaining 512 KiB.
        expect(cache.currentSizeBytes, 112 * 56 * 4);
        expect(
          await CoverPalette.resolve(file.path, Brightness.light),
          same(scheme),
        );
      } finally {
        cache.clear();
        cache.clearLiveImages();
        await directory.delete(recursive: true);
      }
    });
  });

  testWidgets('white and near-black artwork keeps neutral colours', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('neutral-cover-');
      try {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 100, 100),
          Paint()..color = Colors.white,
        );
        canvas.drawRect(
          const Rect.fromLTWH(50, 0, 50, 100),
          Paint()..color = const Color(0xff02020f),
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(100, 100);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        final file = File('${directory.path}/monochrome.png');
        await file.writeAsBytes(bytes!.buffer.asUint8List());

        expect(
          await CoverPalette.resolve(file.path, Brightness.dark),
          isNotNull,
        );
        // The navy-black half has no visible hue: the colours stay gray.
        final colors = CoverPalette.colors(file.path);
        expect(colors.neutral, isTrue);
        expect(colors.surface.r, colors.surface.g);
        expect(colors.surface.g, colors.surface.b);
      } finally {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        await directory.delete(recursive: true);
      }
    });
  });
}
