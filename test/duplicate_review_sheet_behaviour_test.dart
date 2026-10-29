import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/models/local_library_item.dart';
import 'package:sistrum/providers/library_database_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/services/library/library_database.dart';
import 'package:sistrum/services/library/library_schema.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/sheets/duplicate_review_sheet.dart';

import 'support/pump_until.dart';
import 'support/sqlite_process_database.dart';

/// Fixed defaults: the glass dialogs read settings, and the test has no
/// shared-preferences plugin to load them from.
class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

/// Serves the sheet's real duplicate query from a seeded SQLite library.
/// The database getter is overridden because the duplicate lookup is an
/// extension method, which a subclass cannot replace directly.
class _Library extends Fake implements LibraryDatabase {
  _Library(this.db);

  final SqliteProcessDatabase db;
  int reads = 0;
  int failuresLeft = 0;

  @override
  Future<Database> get database async {
    reads++;
    if (failuresLeft > 0) {
      failuresLeft--;
      throw StateError('database locked');
    }
    return db;
  }
}

/// Records what the sheet asked the local library to forget, and drops the
/// matching index rows the way the real notifier does.
class _LocalLibrary extends LocalLibraryNotifier {
  _LocalLibrary(this.db, this.removed);

  final SqliteProcessDatabase db;
  final List<String> removed;

  @override
  LocalLibraryState build() => LocalLibraryState();

  @override
  Future<void> removePhysicalFiles(Iterable<String> filePaths) async {
    for (final path in filePaths) {
      removed.add(path);
      await db.delete('library', where: 'file_path = ?', whereArgs: [path]);
    }
  }
}

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  late Directory directory;
  late SqliteProcessDatabase db;
  late _Library library;
  late List<String> removed;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('duplicates-');
    db = await SqliteProcessDatabase.open();
    await LibrarySchema.create(db, LibrarySchema.version);
    library = _Library(db);
    removed = [];
  });

  tearDown(() async {
    await db.close();
    directory.deleteSync(recursive: true);
  });

  /// The sheet reads and writes SQLite through a child process, which only
  /// progresses while real time passes. Wait for [condition] before settling.
  Future<void> waitUntil(
    WidgetTester tester,
    bool Function() condition,
    String description,
  ) async {
    // Build the frame that started the work before checking for its end.
    await tester.pump();
    await pumpUntilTrue(tester, condition, description: description);
    await tester.pumpAndSettle();
  }

  /// The sheet shows a spinner on Keep best for all while a delete is
  /// pending, including while its confirmation is open, so fixed time is used
  /// instead of waiting for the frames to settle.
  Future<void> settleDialog(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 500));

  bool loaded(WidgetTester tester) =>
      find.byType(CircularProgressIndicator).evaluate().isEmpty;

  /// A real audio file, so deleting it exercises the file-system path.
  String audioFile(String name) {
    final file = File('${directory.path}/$name')..writeAsStringSync('audio');
    return file.path;
  }

  Future<void> addRow(
    String id,
    String path, {
    required String isrc,
    required String title,
    String artist = 'Artist',
    String? format,
    int? bitDepth,
    int? sampleRate,
    int? bitrate,
  }) => db.insert('library', {
    'id': id,
    'track_name': title,
    'artist_name': artist,
    'album_name': 'Album',
    'file_path': path,
    'isrc': isrc,
    'duration': 180,
    'format': format,
    'bitrate': bitrate,
    'bit_depth': bitDepth,
    'sample_rate': sampleRate,
    'scanned_at': '2026-10-10',
    'source_id': LocalLibraryItem.legacySourceId,
  });

  /// Seeds two copies of one recording (FLAC best, MP3 lower) and two Opus
  /// copies of another. Returns the copy paths.
  Future<({String flac, String mp3, String opusHigh, String opusLow})>
  seedLibrary() async {
    final flac = audioFile('Night Song.flac');
    final mp3 = audioFile('Night Song.mp3');
    final opusHigh = audioFile('Other Song.opus');
    final opusLow = audioFile('Other Song copy.opus');
    await addRow(
      'flac',
      flac,
      isrc: 'USABC2600001',
      title: 'Night Song',
      format: 'flac',
      bitDepth: 24,
      sampleRate: 96000,
    );
    await addRow(
      'mp3',
      mp3,
      isrc: 'USABC2600001',
      title: 'Night Song',
      format: 'mp3',
      bitrate: 320000,
      sampleRate: 44100,
    );
    await addRow(
      'opus-high',
      opusHigh,
      isrc: 'USABC2600002',
      title: 'Other Song',
      format: 'opus',
      bitrate: 128000,
    );
    await addRow(
      'opus-low',
      opusLow,
      isrc: 'USABC2600002',
      title: 'Other Song',
      bitrate: 96000,
    );
    return (flac: flac, mp3: mp3, opusHigh: opusHigh, opusLow: opusLow);
  }

  Future<void> pumpSheet(WidgetTester tester, {Widget? home}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          libraryDatabaseProvider.overrideWithValue(library),
          localLibraryProvider.overrideWith(() => _LocalLibrary(db, removed)),
        ],
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home ?? const Scaffold(body: DuplicateReviewSheet()),
        ),
      ),
    );
    await waitUntil(tester, () => loaded(tester), 'the duplicate list to load');
  }

  testWidgets('shows the empty message when there are no duplicates', (
    tester,
  ) async {
    await pumpSheet(tester);
    expect(find.text(en.duplicatesEmpty), findsOneWidget);
    expect(find.text(en.duplicatesKeepBestAll), findsNothing);
  });

  testWidgets('lists each copy with its quality, path and shared ISRC', (
    tester,
  ) async {
    final copies = (await tester.runAsync(seedLibrary))!;
    await pumpSheet(tester);

    expect(find.text('Night Song'), findsOneWidget);
    expect(find.text('Artist • USABC2600001'), findsOneWidget);
    expect(find.text('24/96 FLAC'), findsOneWidget);
    expect(find.text('320k MP3'), findsOneWidget);
    expect(find.text(copies.flac), findsOneWidget);
    expect(find.text(copies.mp3), findsOneWidget);
    expect(find.text('Other Song'), findsOneWidget);
    expect(find.text('128k OPUS'), findsOneWidget);
    // Without a stored format the label comes from the file extension.
    expect(find.text('96k OPUS'), findsOneWidget);
    expect(find.text(en.duplicatesKeepBest), findsNWidgets(2));
    expect(find.text(en.duplicatesKeepBestAll), findsOneWidget);
    expect(find.text(en.duplicatesEmpty), findsNothing);
  });

  testWidgets('keep best deletes the lower copies once confirmed', (
    tester,
  ) async {
    final copies = (await tester.runAsync(seedLibrary))!;
    await pumpSheet(tester);

    await tester.tap(find.text(en.duplicatesKeepBest).first);
    await settleDialog(tester);
    expect(
      find.text(en.duplicatesKeepBestMessage(1, 'Night Song')),
      findsOneWidget,
    );

    await tester.tap(find.text(en.dialogDelete));
    await waitUntil(
      tester,
      () => loaded(tester) && find.text('24/96 FLAC').evaluate().isEmpty,
      'the reloaded list without the deleted copy',
    );

    expect(File(copies.mp3).existsSync(), isFalse);
    expect(File(copies.flac).existsSync(), isTrue);
    expect(File(copies.opusLow).existsSync(), isTrue);
    expect(removed, [copies.mp3]);
    expect(find.text(en.snackbarDeletedTracks(1)), findsOneWidget);
    // The recording has one copy left, so it is no longer a duplicate.
    expect(find.text('24/96 FLAC'), findsNothing);
    expect(find.text('Other Song'), findsOneWidget);
    expect(library.reads, greaterThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling keep best leaves every copy on disk', (tester) async {
    final copies = (await tester.runAsync(seedLibrary))!;
    await pumpSheet(tester);

    await tester.tap(find.text(en.duplicatesKeepBest).first);
    await settleDialog(tester);
    await tester.tap(find.text(en.dialogCancel));
    await settleDialog(tester);

    expect(File(copies.mp3).existsSync(), isTrue);
    expect(removed, isEmpty);
    expect(find.text('24/96 FLAC'), findsOneWidget);
    expect(find.text('320k MP3'), findsOneWidget);
  });

  testWidgets('a single row delete removes only that copy after confirmation', (
    tester,
  ) async {
    final copies = (await tester.runAsync(seedLibrary))!;
    await pumpSheet(tester);

    // Row order: Night Song FLAC, Night Song MP3, Other Song high, Other low.
    await tester.tap(find.byTooltip(en.dialogDelete).at(1));
    await settleDialog(tester);
    expect(
      find.text(en.duplicatesDeleteCopyMessage('Night Song')),
      findsOneWidget,
    );
    await tester.tap(find.text(en.dialogDelete));
    await waitUntil(
      tester,
      () => loaded(tester) && find.text('320k MP3').evaluate().isEmpty,
      'the reloaded list without the deleted copy',
    );

    expect(File(copies.mp3).existsSync(), isFalse);
    expect(File(copies.flac).existsSync(), isTrue);
    expect(removed, [copies.mp3]);
    expect(find.text('320k MP3'), findsNothing);
    expect(find.text('24/96 FLAC'), findsNothing);
    expect(find.text('Other Song'), findsOneWidget);
  });

  testWidgets(
    'keep best for all asks first and then removes every lower copy',
    (tester) async {
      final copies = (await tester.runAsync(seedLibrary))!;
      await pumpSheet(tester);

      await tester.tap(find.text(en.duplicatesKeepBestAll));
      await settleDialog(tester);
      expect(
        find.textContaining(
          en.duplicatesKeepBestAllMessage(2, 2).split('\n').first,
        ),
        findsOneWidget,
      );
      await tester.tap(find.text(en.dialogCancel));
      await settleDialog(tester);
      expect(removed, isEmpty);
      expect(File(copies.opusLow).existsSync(), isTrue);

      await tester.tap(find.text(en.duplicatesKeepBestAll));
      await settleDialog(tester);
      await tester.tap(find.text(en.dialogDelete));
      await waitUntil(
        tester,
        () =>
            loaded(tester) &&
            find.text(en.duplicatesEmpty).evaluate().isNotEmpty,
        'the reloaded list to report no duplicates',
      );

      expect(removed, unorderedEquals([copies.mp3, copies.opusLow]));
      expect(File(copies.mp3).existsSync(), isFalse);
      expect(File(copies.opusLow).existsSync(), isFalse);
      expect(File(copies.flac).existsSync(), isTrue);
      expect(File(copies.opusHigh).existsSync(), isTrue);
      expect(find.text(en.snackbarDeletedTracks(2)), findsOneWidget);
      expect(find.text(en.duplicatesEmpty), findsOneWidget);
    },
  );

  testWidgets('a failed lookup shows the error and retry loads the groups', (
    tester,
  ) async {
    await tester.runAsync(seedLibrary);
    library.failuresLeft = 1;
    await pumpSheet(tester);

    expect(find.text('Night Song'), findsNothing);
    expect(find.text(en.dialogRetry), findsOneWidget);

    await tester.tap(find.text(en.dialogRetry));
    await waitUntil(tester, () => loaded(tester), 'the retried list to load');
    expect(find.text('Night Song'), findsOneWidget);
    expect(library.reads, 2);
  });

  testWidgets('DuplicateReviewSheet.show presents the titled sheet', (
    tester,
  ) async {
    await tester.runAsync(seedLibrary);
    await pumpSheet(
      tester,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => DuplicateReviewSheet.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await waitUntil(tester, () => loaded(tester), 'the sheet to load');
    expect(find.text(en.duplicatesTitle), findsOneWidget);
    expect(find.text('Night Song'), findsOneWidget);
    expect(find.text(en.duplicatesKeepBestAll), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
