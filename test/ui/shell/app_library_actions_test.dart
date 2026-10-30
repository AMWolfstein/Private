import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/core/models/unified_library_item.dart';
import 'package:sistrum/widgets/library/local_song_menu.dart';
import 'package:sistrum/widgets/library/batch_track_actions.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/primitives/app_action_button.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:sistrum/widgets/selection/selection_action_button.dart';
import 'package:sistrum/widgets/selection/selection_bottom_bar.dart';
import 'package:sistrum/screens/library/local_album/local_album_screen.dart';
import 'package:sistrum/services/library/database/library_database.dart';

Widget _app(
  Widget child, {
  Brightness brightness = Brightness.dark,
  TargetPlatform? platform,
}) => ProviderScope(
  child: MaterialApp(
    theme: AppTheme.build(brightness).copyWith(platform: platform),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void _mockMetadataFile(WidgetTester tester) {
  const channel = MethodChannel('com.amwolfstein.sistrum/backend');
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    channel,
    (call) async => switch (call.method) {
      'safStat' => jsonEncode({'exists': true, 'size': 100}),
      'readFileMetadata' => jsonEncode({'title': 'Track', 'artist': 'Artist'}),
      'getSafFileModTimes' => '{}',
      _ => null,
    },
  );
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))).load();
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Sistrum selection actions remain accessible on narrow screens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var selectedAll = false;
    var closed = false;
    var deleted = false;
    var gainApplied = false;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Align(
            alignment: Alignment.bottomCenter,
            child: SelectionBottomBar(
              selectedCount: 1,
              allSelected: false,
              onClose: () => closed = true,
              onToggleSelectAll: () => selectedAll = true,
              bottomPadding: 0,
              children: [
                SelectionActionButton(
                  icon: Icons.graphic_eq,
                  label: 'ReplayGain 1 track',
                  onPressed: () => gainApplied = true,
                  colorScheme: Theme.of(context).colorScheme,
                ),
                const SizedBox(height: 8),
                DestructiveSelectionButton(
                  count: 1,
                  colorScheme: Theme.of(context).colorScheme,
                  onPressed: () => deleted = true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('Select All'));
    await _tapVisible(tester, find.text('ReplayGain 1 track'));
    await _tapVisible(tester, find.byIcon(CupertinoIcons.trash));
    await _tapVisible(tester, find.byIcon(CupertinoIcons.xmark));
    expect(
      (selectedAll, gainApplied, deleted, closed),
      (true, true, true, true),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Sistrum ReplayGain cancellation restores selection without analysis',
    (tester) async {
      bool? confirmed;
      var exitedSelection = false;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => CupertinoButton(
              onPressed: () => runBatchReplayGain(
                context,
                [
                  UnifiedLibraryItem(
                    LocalLibraryItem(
                      id: 'track',
                      trackName: 'Track',
                      artistName: 'Artist',
                      albumName: 'Album',
                      filePath: '/missing/track.flac',
                      scannedAt: DateTime(2026),
                    ),
                  ),
                ],
                database: LibraryDatabase.instance,
                onExitSelectionMode: () => exitedSelection = true,
                onConfirmClosed: (value) async => confirmed = value,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await _tapVisible(tester, find.text('Open'));
      expect(find.byType(AppAlertDialog), findsOneWidget);
      await _tapVisible(tester, find.text('Cancel'));
      expect(confirmed, isFalse);
      expect(exitedSelection, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Sistrum metadata editor keeps edited text and Save available', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    _mockMetadataFile(tester);
    await tester.pumpWidget(
      _app(
        _SongMenuHarness(
          localItem: LocalLibraryItem(
            id: 'edit-track',
            trackName: 'Track',
            artistName: 'Artist',
            albumName: 'Album',
            filePath: 'content://library/document/edit-track.flac',
            scannedAt: DateTime(2026),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byIcon(CupertinoIcons.ellipsis));
    await tester.tap(find.text('Edit Metadata'));
    await tester.pump(const Duration(milliseconds: 400));
    // The editor extracts its preview through real temporary-file I/O.
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 100; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
      }
    });
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
    final title = find.byWidgetPredicate(
      (widget) =>
          widget is CupertinoTextField && widget.controller?.text == 'Track',
    );
    await tester.ensureVisible(title);
    await tester.enterText(title, 'Edited track');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('Edited track'), findsOneWidget);
    expect(find.widgetWithText(AppActionButton, 'Save'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _SongMenuHarness extends ConsumerWidget {
  const _SongMenuHarness({required this.localItem});
  final LocalLibraryItem localItem;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: IconButton(
        icon: const Icon(CupertinoIcons.ellipsis),
        onPressed: () => showLocalSongMenu(context, ref, localItem),
      ),
    ),
  );
}
