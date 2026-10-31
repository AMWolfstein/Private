part of 'design_system_test.dart';

void _registerDesignSystem2() {
  group('AppSliverHeader', () {
    testWidgets('tab root variant shows the title without a back button', (
      tester,
    ) async {
      await tester.pumpWidget(
        _hostSliver(const AppSliverHeader.tabRoot(title: 'Library')),
      );

      expect(find.text('Library'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.back), findsNothing);
    });

    testWidgets('page variant shows a back button that pops the route', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: MaterialTestTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                        body: CustomScrollView(
                          slivers: [AppSliverHeader.page(title: 'Downloads')],
                        ),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Downloads'), findsOneWidget);

      await tester.tap(find.byIcon(CupertinoIcons.back));
      await tester.pumpAndSettle();
      expect(find.text('Downloads'), findsNothing);
    });

    testWidgets('expanded title uses the shared type ramp', (tester) async {
      await tester.pumpWidget(
        _hostSliver(const AppSliverHeader.tabRoot(title: 'Home')),
      );

      final style = tester.widget<Text>(find.text('Home')).style!;
      expect(style.fontSize, AppTokens.standard.headerExpandedTitleSize);
    });

    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets(
        'collapsed page title clears leading control on ${platform.name}',
        (tester) async {
          final controller = ScrollController();
          addTearDown(controller.dispose);
          final topInset = platform == TargetPlatform.iOS ? 59.0 : 24.0;

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: MaterialTestTheme.light().copyWith(platform: platform),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: const Size(430, 932),
                    padding: EdgeInsets.only(top: topInset),
                  ),
                  child: Scaffold(
                    body: CustomScrollView(
                      controller: controller,
                      slivers: const [
                        AppSliverHeader.page(title: 'Metadata'),
                        SliverToBoxAdapter(child: SizedBox(height: 1200)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );

          controller.jumpTo(AppTokens.standard.headerExpandedHeight);
          await tester.pump();

          final title = find.text('Metadata');
          final backIcon = find.byIcon(CupertinoIcons.back);
          expect(
            tester.getRect(title).overlaps(tester.getRect(backIcon)),
            isFalse,
          );
          expect(
            tester.widget<Text>(title).style?.fontSize,
            AppTokens.standard.headerCollapsedTitleSize,
          );
        },
      );
    }

    test('is the only collapsing header implementation left', () {
      final offenders = _libSources()
          .where(
            (file) =>
                file.readAsStringSync().contains('expandedTitleScale') &&
                _basename(file) != 'app_sliver_header.dart',
          )
          .map(_basename)
          .toList();

      expect(
        offenders,
        isEmpty,
        reason:
            'Collapsing headers must go through AppSliverHeader so the type '
            'ramp cannot fork again.',
      );
    });
  });

  group('AppBottomSheet', () {
    testWidgets('supplies one handle plus the title block', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: MaterialTestTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showAppBottomSheet<void>(
                    context: context,
                    title: 'Open on',
                    subtitle: 'Track - Artist',
                    builder: (_) => const Text('body'),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(AppSheetHandle), findsOneWidget);
      expect(find.text('Open on'), findsOneWidget);
      expect(find.text('Track - Artist'), findsOneWidget);
      expect(find.text('body'), findsOneWidget);
    });

    testWidgets('sheet shape comes from the token scale', (tester) async {
      final shape =
          MaterialTestTheme.light().bottomSheetTheme.shape!
              as RoundedRectangleBorder;
      final radius = shape.borderRadius.resolve(TextDirection.ltr).topLeft.x;

      expect(radius, AppTokens.standard.radiusSheet);
    });

    test('no screen hand-rolls a drag handle any more', () {
      final handlePattern = RegExp(
        r'height:\s*4,[\s\S]{0,200}?BorderRadius\.circular\(2\)',
      );
      final offenders = _libSources()
          .where(
            (file) =>
                handlePattern.hasMatch(file.readAsStringSync()) &&
                _basename(file) != 'app_bottom_sheet.dart',
          )
          .map(_basename)
          .toList();

      expect(
        offenders,
        isEmpty,
        reason: 'Use AppSheetHandle instead of rebuilding the pill.',
      );
    });

    test('no call site overrides the modal sheet shape', () {
      final shapeOverride = RegExp(
        r'shape:\s*(?:const\s+)?RoundedRectangleBorder\(\s*borderRadius:\s*'
        r'(?:const\s+)?BorderRadius\.vertical\(',
      );
      final offenders = _libSources()
          .where(
            (file) =>
                shapeOverride.hasMatch(file.readAsStringSync()) &&
                _basename(file) != 'app_theme.dart',
          )
          .map(_basename)
          .toList();

      expect(
        offenders,
        isEmpty,
        reason:
            'Sheet radius belongs to bottomSheetTheme, which reads '
            'AppTokens.radiusSheet.',
      );
    });
  });

  group('TrackCard', () {
    Widget host(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: MaterialTestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

    testWidgets('lays out leading, title, subtitle and trailing', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const TrackCard(
            leading: Icon(Icons.music_note),
            title: 'Song',
            subtitle: Text('Artist'),
            trailing: Icon(Icons.play_arrow),
          ),
        ),
      );

      expect(find.text('Song'), findsOneWidget);
      expect(find.text('Artist'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('selection mode swaps the trailing action for a tick', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const TrackCard(
            leading: Icon(Icons.music_note),
            title: 'Song',
            trailing: Icon(Icons.play_arrow),
            isSelectionMode: true,
            isSelected: true,
          ),
        ),
      );

      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('flat style keeps the row transparent', (tester) async {
      await tester.pumpWidget(
        host(
          const TrackCard(
            leading: SizedBox.shrink(),
            title: 'Song',
            style: TrackCardStyle.flat,
          ),
        ),
      );

      final card = tester.widget<Card>(find.byType(Card));
      expect(card.color, Colors.transparent);
    });

    testWidgets('flat style keeps trailing actions near the card edge', (
      tester,
    ) async {
      const trailingKey = Key('flat-trailing');
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 320,
            child: TrackCard(
              leading: SizedBox(width: 24),
              title: 'Song',
              style: TrackCardStyle.flat,
              trailing: SizedBox(key: trailingKey, width: 48, height: 48),
            ),
          ),
        ),
      );

      final cardRect = tester.getRect(find.byType(Card));
      final trailingRect = tester.getRect(find.byKey(trailingKey));
      // Card's render box includes its 8dp flat-row margin; content itself is
      // inset another 6dp from the painted card edge.
      expect(cardRect.right - trailingRect.right, 14);
    });
  });
}
