import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/providers/player_metadata_controller.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/utils/lyrics/lyric_models.dart';
import 'package:sistrum/utils/playback/playback_seek_preview.dart';
import 'package:sistrum/widgets/player/lyrics/player_lyrics.dart';
import 'package:sistrum/widgets/primitives/app_loading_indicator.dart';
import 'package:sistrum/widgets/player/lyrics/player_lyrics_section.dart';

import '../../../support/library_section_harness.dart';

/// A metadata controller with fixed lyrics and loading state, for the view.
class _FixedMetadata extends PlayerMetadataController {
  _FixedMetadata({
    this.fixedLyrics = ParsedLyrics.empty,
    this.isLoading = false,
  });

  final ParsedLyrics fixedLyrics;
  final bool isLoading;

  @override
  ParsedLyrics get lyrics => fixedLyrics;

  @override
  bool get loading => isLoading;
}

Future<void> _pump(
  WidgetTester tester,
  PlayerMetadataController metadata,
) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [settingsProvider.overrideWith(LibrarySectionSettings.new)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: LyricsCoveredBottom(
            height: 0,
            child: PlayerLyricsSection(
              metadata: metadata,
              seekPreview: PlaybackSeekPreview(),
              colorScheme: const ColorScheme.dark(),
              isActive: true,
            ),
          ),
        ),
      ),
    ),
  );
  // The loading indicator animates forever, so pump a fixed time instead.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('a track with no lyrics says so', (tester) async {
    await _pump(tester, _FixedMetadata());
    final l10n = AppLocalizations.of(
      tester.element(find.byType(PlayerLyricsSection)),
    );
    expect(find.text(l10n.nowPlayingNoLyrics), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a track whose lyrics are loading shows a progress indicator', (
    tester,
  ) async {
    await _pump(tester, _FixedMetadata(isLoading: true));
    expect(find.byType(AppLoadingIndicator), findsOneWidget);
  });

  testWidgets('untimed lyrics show their plain text', (tester) async {
    await _pump(
      tester,
      _FixedMetadata(
        fixedLyrics: const ParsedLyrics(
          synced: false,
          wordSynced: false,
          lines: [],
          plainText: 'First line\nSecond line',
        ),
      ),
    );
    expect(find.textContaining('First line'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
