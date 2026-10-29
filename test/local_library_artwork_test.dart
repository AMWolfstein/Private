import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/local_library_item.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/providers/library_browse_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/screens/library/local_album_screen.dart';
import 'package:sistrum/screens/library/app_library_screen.dart';
import 'package:sistrum/services/library/embedded_cover_resolver.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/cached_cover_image.dart';
import 'package:sistrum/widgets/library/local_library_artwork_builder.dart';
import 'package:sistrum/widgets/header/app_artist_header.dart';

class _Settings extends SettingsNotifier {
  // The cover drift repeats forever and would keep pumpAndSettle waiting.
  @override
  AppSettings build() => const AppSettings(animatedAlbumArtwork: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.amwolfstein.sistrum/backend');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aRZkAAAAASUVORK5CYII=',
  );
  late Directory directory;
  late File audio;
  late File scannedCover;
  late int extractions;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('local_album_artwork_');
    audio = await File('${directory.path}/song.flac').writeAsBytes([0, 1]);
    scannedCover = File('${directory.path}/missing.jpg');
    EmbeddedCoverResolver.setPersistentCacheDirectoryForTesting(
      Directory('${directory.path}/previews'),
    );
    EmbeddedCoverResolver.setValidationClockForTesting(() => DateTime(2026));
    extractions = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'extractCoverToFile') {
        extractions++;
        final args = call.arguments as Map<Object?, Object?>;
        await File(args['output_path'] as String).writeAsBytes(png);
        return jsonEncode({'success': true});
      }
      return null;
    });
  });

  tearDown(() async {
    await EmbeddedCoverResolver.resetMemoryStateForTesting(
      preservePersistentFiles: false,
    );
    EmbeddedCoverResolver.setPersistentCacheDirectoryForTesting(null);
    messenger.setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  Widget app(Widget home, {bool sistrum = false}) => ProviderScope(
    overrides: [settingsProvider.overrideWith(_Settings.new)],
    child: MaterialApp(
      theme: AppTheme.build(sistrum ? Brightness.dark : Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );

  // File I/O completes outside Flutter's fake clock. Yield event-loop turns
  // until the observable result arrives, without sleeping for a fixed delay.
  Future<void> pumpUntil(WidgetTester tester, bool Function() ready) async {
    for (var turn = 0; turn < 200 && !ready(); turn++) {
      await tester.runAsync(() => scannedCover.stat());
      await tester.pump();
    }
    expect(ready(), isTrue);
  }

  Future<String?> playerPreview(WidgetTester tester) =>
      tester.runAsync<String?>(() async {
        final preview = await EmbeddedCoverResolver.resolveOrExtract(
          audio.path,
        );
        await EmbeddedCoverResolver.resolveOrExtract(audio.path);
        await EmbeddedCoverResolver.waitForPreviewValidationForTesting();
        return preview;
      });

  for (final missing in [true, false]) {
    testWidgets('builder recovers ${missing ? 'missing' : 'empty'} thumbnail', (
      tester,
    ) async {
      final recovered = Completer<String>();
      final preview = await playerPreview(tester);
      expect(preview, isNotNull);
      await tester.runAsync(() async {
        if (!missing) await scannedCover.writeAsBytes([]);
        await tester.pumpWidget(
          app(
            LocalLibraryArtworkBuilder(
              coverPath: scannedCover.path,
              filePath: audio.path,
              builder: (_, path) {
                if (path != null &&
                    path != scannedCover.path &&
                    !recovered.isCompleted) {
                  recovered.complete(path);
                }
                return Text(path ?? 'placeholder');
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
      });
      await tester.pumpAndSettle();
      await pumpUntil(tester, () => recovered.isCompleted);
      expect(
        await tester.runAsync(
          () async => File(await recovered.future).readAsBytes(),
        ),
        png,
      );
      await tester.pumpAndSettle();
      expect(extractions, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('valid scanned file URI avoids extraction', (tester) async {
    await tester.runAsync(() async {
      await scannedCover.writeAsBytes(png);
      await tester.pumpWidget(
        app(
          LocalLibraryArtworkBuilder(
            coverPath: scannedCover.uri.toString(),
            filePath: audio.path,
            builder: (_, path) => Text(path ?? 'placeholder'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    });
    expect(find.text(scannedCover.path), findsOneWidget);
    expect(extractions, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'late scan validation cannot replace another album or update after dispose',
    (tester) async {
      final nextCover = await tester.runAsync(
        () => File('${directory.path}/next.jpg').writeAsBytes(png),
      );
      Widget artwork(String path) => app(
        LocalLibraryArtworkBuilder(
          coverPath: path,
          filePath: null,
          builder: (_, cover) => Text(cover ?? 'placeholder'),
        ),
      );
      await tester.pumpWidget(artwork(scannedCover.path));
      await tester.pumpWidget(artwork(nextCover!.path));
      await tester.runAsync(() => scannedCover.stat());
      await tester.pump();
      expect(find.text(nextCover.path), findsOneWidget);
      await tester.pumpWidget(artwork(scannedCover.path));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => scannedCover.stat());
      await tester.pump();
      expect(extractions, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final sistrum in [true]) {
    testWidgets('blank album cover keeps the scanned track cover ($sistrum)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await scannedCover.writeAsBytes(png);
        await tester.pumpWidget(
          app(
            LocalAlbumScreen(
              albumName: 'Album',
              artistName: 'Artist',
              coverPath: '   ',
              tracks: [
                LocalLibraryItem(
                  id: 'song',
                  trackName: 'Song',
                  artistName: 'Artist',
                  albumName: 'Album',
                  filePath: audio.path,
                  coverPath: scannedCover.path,
                  scannedAt: DateTime(2026),
                ),
              ],
            ),
            sistrum: sistrum,
          ),
        );
        await tester.pumpAndSettle();
      });
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppArtistSurface>(find.byType(AppArtistSurface))
            .imageSource,
        scannedCover.path,
      );
      expect(extractions, 0);
      expect(tester.takeException(), isNull);
    });

    for (final stale in [false, true]) {
      testWidgets('album header recovers artwork ($sistrum, stale: $stale)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(430, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        // The player has already recovered artwork, as in the tester report.
        final preview = await playerPreview(tester);
        await tester.runAsync(() async {
          await tester.pumpWidget(
            app(
              LocalAlbumScreen(
                albumName: 'Album',
                artistName: 'Artist',
                coverPath: stale ? scannedCover.path : null,
                tracks: [
                  LocalLibraryItem(
                    id: 'song',
                    trackName: 'Song',
                    artistName: 'Artist',
                    albumName: 'Album',
                    filePath: audio.path,
                    coverPath: stale ? scannedCover.path : null,
                    scannedAt: DateTime(2026),
                  ),
                ],
              ),
              sistrum: sistrum,
            ),
          );
          await tester.pumpAndSettle();
        });
        await tester.pumpAndSettle();
        await pumpUntil(
          tester,
          () =>
              tester
                  .widget<AppArtistSurface>(
                    find.byType(AppArtistSurface),
                  )
                  .imageSource ==
              preview,
        );
        expect(extractions, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Sistrum album grid replaces a stale scan path', (tester) async {
    final preview = await playerPreview(tester);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(_Settings.new),
            libraryBrowsePageLoaderProvider.overrideWithValue(
              (request) async => LibraryBrowsePage([
                LibraryBrowseEntry(
                  source: 'local',
                  key: 'album',
                  name: 'Album',
                  artist: 'Artist',
                  cover: scannedCover.path,
                  samplePath: audio.path,
                  trackCount: 1,
                ),
              ]),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.build(Brightness.light),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: AppLibraryScreen(
                page: AppLibraryPage.albums,
                onOpenSection: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    });
    await tester.pumpAndSettle();
    await pumpUntil(
      tester,
      () => tester
          .widgetList<LocalCoverImage>(find.byType(LocalCoverImage))
          .any((image) => image.url == preview),
    );
    expect(extractions, 1);
    expect(tester.takeException(), isNull);
  });
}
