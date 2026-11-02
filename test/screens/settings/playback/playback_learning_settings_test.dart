import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/screens/settings/playback/playback_settings_page.dart';
import 'package:sistrum/services/playback/autoplay/autoplay_ranker.dart';
import 'package:sistrum/services/playback/music_player/music_player_runtime.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';

class _Ranker extends AutoplayRanker {
  final status = ValueNotifier<AutoplayRankEvaluation?>(
    const AutoplayRankEvaluation(outcomes: 0),
  );
  @override
  ValueListenable<AutoplayRankEvaluation?> get evaluation => status;
}

class _Runtime implements MusicPlayerRuntime {
  _Runtime(this.ranker);
  @override
  final AutoplayRanker ranker;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('gapless defaults preserve existing playback and round-trip off', () {
    expect(AppSettings.fromJson({}).gaplessPlayback, isTrue);
    final disabled = const AppSettings().copyWith(gaplessPlayback: false);
    expect(AppSettings.fromJson(disabled.toJson()).gaplessPlayback, isFalse);
  });

  for (final brightness in Brightness.values) {
    testWidgets('gapless gates and live learning summaries ($brightness)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ranker = _Ranker();
      addTearDown(ranker.status.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            musicPlayerRuntimeProvider.overrideWithValue(_Runtime(ranker)),
          ],
          child: MaterialApp(
            theme: AppTheme.build(brightness),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const PlaybackSettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(PlaybackSettingsPage));
      final container = ProviderScope.containerOf(context);
      final notifier = container.read(settingsProvider.notifier);
      await notifier.ensureLoaded();
      await tester.pumpAndSettle();
      Finder gapless() => find.byWidgetPredicate(
        (w) => w is SettingsSwitchItem && w.title == 'Gapless playback',
      );
      expect(tester.widget<SettingsSwitchItem>(gapless()).enabled, isTrue);
      expect(
        tester.getTopLeft(gapless()).dy,
        lessThan(tester.getTopLeft(find.text('AutoMix')).dy),
      );
      notifier.setGaplessPlayback(false);
      await tester.pumpAndSettle();
      expect(tester.widget<SettingsSwitchItem>(gapless()).value, isFalse);
      notifier.setGaplessPlayback(true);
      notifier.setAutoMix(true);
      await tester.pumpAndSettle();
      expect(tester.widget<SettingsSwitchItem>(gapless()).enabled, isFalse);
      expect(tester.widget<SettingsSwitchItem>(gapless()).value, isFalse);
      expect(container.read(settingsProvider).gaplessPlayback, isTrue);
      notifier.setAutoMix(false);
      await tester.pumpAndSettle();
      expect(tester.widget<SettingsSwitchItem>(gapless()).value, isTrue);
      await tester.scrollUntilVisible(
        find.text('Reset recommendation learning').hitTestable(),
        150,
      );
      expect(
        find.text('Ranking tunes to you after 40 Autoplay songs (0 so far)'),
        findsOneWidget,
      );
      ranker.status.value = const AutoplayRankEvaluation(
        outcomes: 40,
        tested: 10,
      );
      await tester.pump();
      expect(
        find.text(
          'Standard ranking until you both keep and skip recent Autoplay songs',
        ),
        findsOneWidget,
      );
      ranker.status.value = const AutoplayRankEvaluation(
        outcomes: 50,
        tested: 12,
        starting: .5,
        learned: .75,
      );
      await tester.pump();
      expect(
        find.text(
          'Tuned to you: 75% accurate on your latest songs (standard 50%)',
        ),
        findsOneWidget,
      );
      ranker.status.value = const AutoplayRankEvaluation(
        outcomes: 60,
        tested: 15,
        starting: .75,
        learned: .5,
      );
      await tester.pump();
      expect(
        find.text(
          'Standard ranking: tuning was not more accurate on your latest songs (50% vs 75%)',
        ),
        findsOneWidget,
      );
      ranker.status.value = const AutoplayRankEvaluation(outcomes: 0);
      await tester.pump();
      expect(
        find.text('Ranking tunes to you after 40 Autoplay songs (0 so far)'),
        findsOneWidget,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(loadBootstrapSettings(prefs).gaplessPlayback, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
