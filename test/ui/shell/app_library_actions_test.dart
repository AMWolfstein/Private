import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/widgets/library/local_song_menu.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/primitives/app_action_button.dart';

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
