import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/services/playback/music_player_service.dart';
import 'package:sistrum/services/playback/music_player_runtime.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/widgets/app_snack_bar.dart';
import 'package:sistrum/widgets/glass/sistrum_chrome.dart';
import 'package:sistrum/widgets/player/playback_feedback.dart';

void main() {
  for (final sistrum in [true]) {
    testWidgets('playback errors show once in Sistrum (dark: $sistrum)', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final runtime = MusicPlayerRuntime(
        dependencies: defaultPlaybackDependencies,
      );
      addTearDown(runtime.dispose);
      final states = StreamController<PlaybackState>();
      addTearDown(states.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            musicPlayerRuntimeProvider.overrideWithValue(runtime),
            playbackStateProvider.overrideWith((_) => states.stream),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: SistrumTheme.build(
              sistrum ? Brightness.dark : Brightness.light,
            ),
            builder: (_, child) =>
                AppScaffoldMessenger(child: PlaybackFeedback(child: child!)),
            home: const Scaffold(body: SizedBox.expand()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final failed = PlaybackState(
        processingState: AudioProcessingState.error,
        errorCode: 1,
        errorMessage: 'Audio output failed',
      );
      states.add(failed);
      await tester.pumpAndSettle();
      expect(
        find.text('Cannot open file: Audio output failed'),
        findsOneWidget,
      );
      expect(find.byType(SistrumGlassPanel), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      states.add(failed.copyWith(updatePosition: const Duration(seconds: 1)));
      await tester.pumpAndSettle();
      expect(find.text('Cannot open file: Audio output failed'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('muted feedback is transient and themed (Sistrum: $sistrum)', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final runtime = MusicPlayerRuntime(
        dependencies: defaultPlaybackDependencies,
      );
      addTearDown(runtime.dispose);
      // Notices emitted before the shell mounts must not be replayed.
      runtime.notifyMutedPlayback();
      final message = sistrum
          ? 'Volume media nol. Lagu dijeda. Tekan play lagi untuk tetap memutar.'
          : 'Media volume is zero. Playback paused. Press play again to continue.';
      await tester.pumpWidget(
        ProviderScope(
          overrides: [musicPlayerRuntimeProvider.overrideWithValue(runtime)],
          child: MaterialApp(
            locale: Locale(sistrum ? 'id' : 'en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: sistrum ? SistrumTheme.build(Brightness.dark) : ThemeData(),
            builder: (_, child) =>
                AppScaffoldMessenger(child: PlaybackFeedback(child: child!)),
            home: const Scaffold(body: SizedBox.expand()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing);
      runtime.notifyMutedPlayback();
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(
        find.byType(SistrumGlassPanel),
        sistrum ? findsOneWidget : findsNothing,
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      runtime.notifyMutedPlayback();
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing);
      // A later mute episode may emit the exact same warning again.
      runtime.notifyMutedPlayback();
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
