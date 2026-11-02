import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/services/playback/audio/replaygain_progress.dart';
import 'package:sistrum/widgets/settings/app_replay_gain_progress_view.dart';

Future<void> _pump(
  WidgetTester tester,
  ReplayGainProgress? progress, {
  Locale locale = const Locale('en'),
  double textScale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    locale: locale,
    theme: AppTheme.build(Brightness.dark),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
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
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0,
      );
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
      expect(find.text('2 written'), findsOneWidget);
      expect(find.text('1 unchanged'), findsOneWidget);
      expect(find.text('1 failed'), findsOneWidget);
      expect(find.text('1 deferred'), findsOneWidget);
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
  for (final locale in [const Locale('en'), const Locale('ar')]) {
    testWidgets('narrow $locale progress wraps counts at large text sizes', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        const ReplayGainProgress(
          phase: ReplayGainPhase.waitingForCharging,
          checked: 1,
          total: 1966,
          written: 10,
          unchanged: 100,
          failed: 2,
          deferred: 5,
          completedUnits: 1,
          totalUnits: 4000,
        ),
        locale: locale,
        textScale: 2,
      );
      expect(find.byType(Wrap), findsOneWidget);
      final bar = find.byType(LinearProgressIndicator);
      expect(tester.widget<LinearProgressIndicator>(bar).value, 1 / 4000);
      expect(tester.getRect(bar).left, greaterThanOrEqualTo(0));
      expect(tester.getRect(bar).right, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    });
  }
}
