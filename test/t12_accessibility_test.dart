import 'dart:math' as math;
import 'dart:ui' show Tristate;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/primitives/app_choice_chip.dart';
import 'package:sistrum/widgets/primitives/app_switch.dart';
import 'package:sistrum/widgets/status/audio_quality_badges.dart';
import 'package:sistrum/widgets/library/local_song_row.dart';
import 'package:sistrum/widgets/sheets/metadata_text_field.dart';
import 'package:sistrum/widgets/header/header_controls.dart';

/// WCAG 2.1 relative-contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Widget _host(Widget child, {Brightness brightness = Brightness.light}) {
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.build(brightness),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// The colour the given text actually paints with.
Color _textColor(WidgetTester tester, Finder text) {
  final rich = tester.widget<RichText>(
    find.descendant(of: text, matching: find.byType(RichText)).first,
  );
  return rich.text.style!.color!;
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'choice chip is a selected 48dp button in a group ($brightness)',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _host(
            AppChoiceChip(
              label: const Text('One'),
              selected: true,
              singleChoice: true,
              onSelected: (_) {},
            ),
            brightness: brightness,
          ),
        );

        expect(
          tester.getSize(find.byType(CupertinoButton)).height,
          greaterThanOrEqualTo(48),
        );
        final flags = tester
            .getSemantics(find.byType(AppChoiceChip))
            .getSemanticsData()
            .flagsCollection;
        expect(flags.isSelected, Tristate.isTrue);
        expect(flags.isButton, isTrue);
        expect(flags.isInMutuallyExclusiveGroup, isTrue);
        handle.dispose();
      },
    );

    testWidgets('selected choice chip label meets AA ($brightness)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          AppChoiceChip(
            label: const Text('One'),
            selected: true,
            singleChoice: true,
            onSelected: (_) {},
          ),
          brightness: brightness,
        ),
      );
      final scheme = Theme.of(
        tester.element(find.byType(AppChoiceChip)),
      ).colorScheme;
      // The chip paints the accent at 12% over the page surface.
      final fill = Color.alphaBlend(
        scheme.primary.withValues(alpha: 0.12),
        scheme.surface,
      );
      final label = _textColor(tester, find.text('One'));
      expect(_contrast(label, fill), greaterThanOrEqualTo(4.5));
    });

    testWidgets('explicit badge meets AA ($brightness)', (tester) async {
      await tester.pumpWidget(
        _host(
          ExplicitBadge(
            colorScheme: AppTheme.build(brightness).colorScheme,
          ),
          brightness: brightness,
        ),
      );
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(ExplicitBadge),
          matching: find.byType(Container),
        ),
      );
      final fill = (container.decoration! as BoxDecoration).color!;
      final label = _textColor(tester, find.text('E'));
      expect(_contrast(label, fill), greaterThanOrEqualTo(4.5));
    });
  }

  testWidgets('switch keeps a 48dp hit box', (tester) async {
    await tester.pumpWidget(_host(AppSwitch(value: true, onChanged: (_) {})));
    final size = tester.getSize(find.byType(InkWell));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));
  });

  testWidgets('song row names the track in its play and menu labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 360,
          child: LocalSongRow(
            title: 'Song',
            artist: 'Artist',
            onPlay: () {},
            onMenu: (_) {},
          ),
        ),
      ),
    );
    expect(find.byTooltip('Play Song by Artist'), findsOneWidget);
    expect(find.byTooltip('More options for Song'), findsOneWidget);
  });

  for (final playing in [false, true]) {
    testWidgets('album play control names its action (playing: $playing)', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 360,
            child: LocalSongRow(
              title: 'Album song',
              artist: '',
              numbered: true,
              isPlaying: playing,
              onPlay: () => taps++,
              onMenu: (_) {},
            ),
          ),
        ),
      );
      final button = find.byTooltip('${playing ? 'Pause' : 'Play'} Album song');
      expect(button, findsOneWidget);
      expect(find.byTooltip('Play Album song by '), findsNothing);
      await tester.tap(button);
      expect(taps, 1);
    });
  }

  testWidgets('explicit badge is a label, not "Explicit E"', (tester) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 360,
          child: LocalSongRow(
            title: 'Song',
            artist: 'Artist',
            onPlay: () {},
            onMenu: (_) {},
            explicit: true,
          ),
        ),
      ),
    );
    final badge = tester.widget<Semantics>(
      find.ancestor(of: find.text('E'), matching: find.byType(Semantics)).first,
    );
    expect(badge.excludeSemantics, isTrue);
    expect(badge.properties.label, 'Explicit');
  });

  testWidgets('album track numbers keep one line at 2x text', (tester) async {
    await tester.pumpWidget(
      _host(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: SizedBox(
            width: 360,
            child: LocalSongRow(
              title: 'Song',
              artist: 'Artist',
              number: 128,
              numbered: true,
              onPlay: () {},
              onMenu: (_) {},
            ),
          ),
        ),
      ),
    );
    final number = tester.widget<Text>(find.text('128'));
    expect(number.maxLines, 1);
    expect(tester.getSize(find.text('128')).width, lessThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('metadata fields expose their visible label', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = TextEditingController(text: 'Value');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 320,
          child: MetadataTextField(
            AppTheme.build(Brightness.light).colorScheme,
            'Title',
            controller,
          ),
        ),
      ),
    );
    final data = tester
        .getSemantics(find.byType(CupertinoTextField))
        .getSemanticsData();
    expect(data.label, 'Title');
    expect(data.value, 'Value');
    handle.dispose();
  });

  testWidgets('default header circle is 48dp', (tester) async {
    await tester.pumpWidget(
      _host(
        HeaderCircleButton(
          icon: CupertinoIcons.back,
          tooltip: 'Back',
          onPressed: () {},
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(IconButton)).height,
      greaterThanOrEqualTo(48),
    );
  });
}
