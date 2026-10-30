import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/screens/listening_statistics_screen.dart';
import 'package:sistrum/services/playback/stats/listening_statistics.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';

typedef _Period = ({int days, int year});

class _Settings extends SettingsNotifier {
  _Settings(this.changes);

  final List<bool> changes;

  @override
  AppSettings build() => const AppSettings();
}

const _alpha = ListeningTrack(
  key: 'alpha',
  title: 'Alpha Song',
  artist: 'Artist One',
  album: 'Album',
);
const _beta = ListeningTrack(
  key: 'beta',
  title: 'Beta Song',
  artist: '   ',
  album: 'Album',
);

final _summary = ListeningSummary(
  milliseconds: 300000,
  plays: 3,
  tracks: const [
    ListeningTotal(_alpha, 180000, 2),
    ListeningTotal(_beta, 120000, 1),
  ],
  artists: const {'Artist One': 180000, 'Artist Two': 120000},
  days: const {'2026-10-01': 60000, '2026-10-02': 240000},
);

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  late List<bool> settingChanges;
  late List<_Period> periods;

  setUp(() {
    settingChanges = [];
    periods = [];
  });

  IconButton nextYearButton(WidgetTester tester) => tester.widget<IconButton>(
    find.ancestor(
      of: find.byTooltip(en.listeningStatsNextYear),
      matching: find.byType(IconButton),
    ),
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    required Future<ListeningSummary> Function(_Period period) summary,
  }) async {
    // Tall enough that every section is inside the lazy sliver cache.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(() => _Settings(settingChanges)),
          listeningSummaryProvider.overrideWith((ref, period) {
            periods.add(period);
            return summary(period);
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ListeningStatisticsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows totals, activity, top artists and tracks for the data', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpScreen(tester, summary: (_) async => _summary);

    expect(find.text(en.listeningStats), findsOneWidget);
    expect(find.text('5 min'), findsOneWidget);
    expect(find.text(en.listeningStatsTotals(3, 2, 2)), findsOneWidget);
    expect(find.text(en.listeningStatsActivity), findsOneWidget);
    expect(find.text('Oct 1'), findsOneWidget);
    expect(find.text('Oct 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Oct 2: 4 min'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    final bars = tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .map((bar) => bar.value)
        .toList();
    expect(bars, [0.25, 1.0]);

    expect(find.text(en.listeningStatsTopArtists), findsOneWidget);
    expect(find.text('Artist Two'), findsOneWidget);
    expect(
      tester.getCenter(find.text('Artist One').first).dy,
      lessThan(tester.getCenter(find.text('Artist Two')).dy),
    );

    expect(find.text(en.listeningStatsTopTracks), findsOneWidget);
    expect(find.text('Alpha Song'), findsOneWidget);
    expect(find.text('Beta Song'), findsOneWidget);
    expect(find.text(en.unknownArtist), findsOneWidget);
    expect(find.text(en.listeningStatsEmpty), findsNothing);
    semantics.dispose();
  });

  testWidgets('a summary without listening shows the empty message only', (
    tester,
  ) async {
    await pumpScreen(tester, summary: (_) async => const ListeningSummary());

    expect(find.text(en.listeningStatsEmpty), findsOneWidget);
    expect(find.text(en.listeningStatsTotals(0, 0, 0)), findsOneWidget);
    expect(find.text(en.listeningStatsActivity), findsNothing);
    expect(find.text(en.listeningStatsTopTracks), findsOneWidget);
  });

  testWidgets('period chips request the matching listening window', (
    tester,
  ) async {
    await pumpScreen(tester, summary: (_) async => _summary);
    final year = DateTime.now().year;

    expect(periods.last, (days: 7, year: year));
    expect(find.byTooltip(en.listeningStatsPreviousYear), findsNothing);

    await tester.tap(find.text(en.listeningStatsDays(30)));
    await tester.pumpAndSettle();
    expect(periods.last, (days: 30, year: year));

    await tester.tap(find.text('$year'));
    await tester.pumpAndSettle();
    expect(periods.last, (days: 0, year: year));
    expect(find.byTooltip(en.listeningStatsPreviousYear), findsOneWidget);
    expect(nextYearButton(tester).onPressed, isNull);

    await tester.tap(find.byTooltip(en.listeningStatsPreviousYear));
    await tester.pumpAndSettle();
    expect(periods.last, (days: 0, year: year - 1));
    expect(nextYearButton(tester).onPressed, isNotNull);
  });

  testWidgets('a failed load shows the error and retry requests it again', (
    tester,
  ) async {
    var attempts = 0;
    await pumpScreen(
      tester,
      summary: (_) async {
        attempts++;
        throw StateError('offline');
      },
    );

    expect(find.text(en.listeningStatsLoadError), findsOneWidget);
    expect(attempts, 1);

    await tester.tap(find.byTooltip(en.dialogRetry));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text(en.listeningStatsLoadError), findsOneWidget);
  });

  testWidgets('recording is always on, so no recording switch is shown', (
    tester,
  ) async {
    await pumpScreen(tester, summary: (_) async => _summary);

    expect(find.byType(SettingsSwitchItem), findsNothing);
    expect(settingChanges, isEmpty);
  });

  testWidgets('clear asks for confirmation and cancel keeps the statistics', (
    tester,
  ) async {
    await pumpScreen(tester, summary: (_) async => _summary);

    await tester.tap(find.text(en.listeningStatsClear));
    await tester.pumpAndSettle();
    expect(find.text(en.listeningStatsClearDescription), findsOneWidget);

    await tester.tap(find.text(en.dialogCancel));
    await tester.pumpAndSettle();
    expect(find.text(en.listeningStatsClearDescription), findsNothing);
    expect(find.text('Alpha Song'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
