import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/services/playback/audio/replaygain_progress.dart';
import 'package:sistrum/widgets/settings/app_replay_gain_progress_view.dart';

Future<void> _pump(WidgetTester tester, ReplayGainProgress? progress) =>
    tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: AppReplayGainProgressView(progress: progress)),
      ),
    );
void main() {
  testWidgets('disabled writer has no progress indicator or loading text', (
    tester,
  ) async {
    await _pump(tester, null);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(Text), findsNothing);
  });
  testWidgets('album phase shows visible counts without reporting completion', (
    tester,
  ) async {
    await _pump(
      tester,
      const ReplayGainProgress(
        phase: ReplayGainPhase.albums,
        checked: 2,
        total: 2,
        completedUnits: 2,
        totalUnits: 5,
      ),
    );
    expect(find.text('Measuring album loudness…'), findsOneWidget);
    expect(find.text('2 of 2 songs checked'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.4,
    );
  });
  for (final phase in [
    ReplayGainPhase.waitingForCharging,
    ReplayGainPhase.waitingForPlayback,
    ReplayGainPhase.failed,
  ]) {
    testWidgets('waiting/error state $phase does not animate a spinner', (
      tester,
    ) async {
      await _pump(tester, ReplayGainProgress(phase: phase));
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  }
  testWidgets(
    'completion distinguishes written unchanged failed and deferred files',
    (tester) async {
      await _pump(
        tester,
        const ReplayGainProgress(
          phase: ReplayGainPhase.completed,
          checked: 5,
          total: 5,
          written: 2,
          unchanged: 1,
          failed: 1,
          deferred: 1,
          completedUnits: 11,
          totalUnits: 11,
        ),
      );
      expect(
        find.text('ReplayGain check finished with errors'),
        findsOneWidget,
      );
      expect(
        find.text('2 written · 1 unchanged · 1 failed · 1 deferred'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        1,
      );
    },
  );
}
