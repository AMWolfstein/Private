part of 'listening_rewind_test.dart';

void _registerListeningRewind2() {
  for (final sistrum in [true]) {
    testWidgets('yearly slides fit landscape with large text ($sistrum)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(780, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final sample = _yearSample();
      final rewind = ListeningRewind.compute(
        range: sample.range,
        summary: sample.summary,
        previousMilliseconds: 0,
        year: ListeningYearDetails(
          monthlyTopArtists: {
            for (var month = 1; month <= 12; month++) month: 'Artist $month',
          },
          loyalArtist: sample.year?.loyalArtist,
          loyalArtistDays: sample.year!.loyalArtistDays,
          firstPlay: sample.year?.firstPlay,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            listeningRewindProvider.overrideWith((ref, period) async => rewind),
          ],
          child: MaterialApp(
            theme: sistrum ? AppTheme.build(Brightness.dark) : ThemeData(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: const TextScaler.linear(1.6),
              ),
              child: child!,
            ),
            home: const ListeningRewindScreen(
              period: ListeningRewindPeriod.year,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final story = tester.getRect(find.byType(PageView));
      for (var i = 0; i < 20; i++) {
        expect(tester.takeException(), isNull);
        await tester.tapAt(Offset(story.right - 40, story.center.dy));
        await tester.pumpAndSettle();
      }
      expect(find.text('That was your 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('no spotlight leaves no banner', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          listeningRewindSpotlightProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: ListeningRewindBanner()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rewind'), findsNothing);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('empty windows explain how to fill a Rewind', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          listeningRewindProvider.overrideWith(
            (ref, period) async => ListeningRewind.compute(
              range: _range,
              summary: const ListeningSummary(),
              previousMilliseconds: 0,
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ListeningRewindScreen(period: ListeningRewindPeriod.year),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Not enough listening'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
  });

  testWidgets('a screen reader stops the story from auto-advancing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          listeningRewindProvider.overrideWith(
            (ref, period) async => _sample(newArtists: {'Fresh'}),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
            child: child!,
          ),
          home: const ListeningRewindScreen(
            period: ListeningRewindPeriod.weeks,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Your Rewind'), findsOneWidget);

    // Two slide durations would move an auto-advancing story twice.
    await tester.pump(const Duration(seconds: 13));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Your Rewind'), findsOneWidget);
    expect(find.text("That's about 2 hours of music"), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a screen reader the story advances on its own', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          listeningRewindProvider.overrideWith(
            (ref, period) async => _sample(newArtists: {'Fresh'}),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ListeningRewindScreen(
            period: ListeningRewindPeriod.weeks,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Your Rewind'), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("That's about 2 hours of music"), findsOneWidget);
  });
}
