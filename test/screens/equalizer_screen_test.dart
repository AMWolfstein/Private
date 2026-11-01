import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/models/equalizer_settings.dart';
import 'package:sistrum/providers/settings/equalizer_provider.dart';
import 'package:sistrum/screens/player/equalizer_screen.dart';
import 'package:sistrum/services/playback/audio/playback_equalizer.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/primitives/app_level_slider.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'Sistrum EQ fits narrow large text and changes band count ($brightness)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        playbackEqualizer.value = const EqualizerSettings();
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final container = ProviderContainer();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.build(brightness),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!,
              ),
              home: const EqualizerScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(container.read(equalizerProvider).settings.enabled, isFalse);
        container
            .read(equalizerProvider.notifier)
            .update(const EqualizerSettings(enabled: true));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('5'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('5'));
        await tester.pumpAndSettle();
        expect(container.read(equalizerProvider).settings.gains.length, 5);
        final fader = find
            .byWidgetPredicate(
              (widget) => widget is AppLevelSlider && widget.vertical,
            )
            .first;
        await tester.ensureVisible(fader);
        await tester.pumpAndSettle();
        await tester.drag(fader, const Offset(0, -30));
        await tester.pumpAndSettle();
        expect(
          container
              .read(equalizerProvider)
              .settings
              .gains
              .any((gain) => gain != 0),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      },
    );
  }

  testWidgets(
    'EQ overview, band reset and compressor controls share live settings',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      playbackEqualizer.value = const EqualizerSettings();
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.build(Brightness.dark),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const EqualizerScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final control = container.read(equalizerProvider.notifier);
      control.update(
        EqualizerSettings(enabled: true, gains: [3, ...List.filled(9, 0.0)]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Custom'), findsWidgets);
      expect(find.byType(CustomPaint), findsWidgets);
      final faders = find.byWidgetPredicate(
        (w) => w is AppLevelSlider && w.vertical,
      );
      await tester.ensureVisible(faders.first);
      await tester.pumpAndSettle();
      final fader = tester.widget<AppLevelSlider>(faders.first);
      expect(fader.value, 3);
      final reset = find.byTooltip('Reset ${fader.semanticLabel}');
      await Scrollable.ensureVisible(tester.element(reset), alignment: .4);
      await tester.pumpAndSettle();
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(container.read(equalizerProvider).settings.gains.first, 0);
      control.update(
        container.read(equalizerProvider).settings.copyWith(compressor: true),
      );
      await tester.pumpAndSettle();
      final attack = find.byWidgetPredicate(
        (w) => w is AppLevelSlider && w.semanticLabel == 'Attack',
      );
      expect(container.read(equalizerProvider).settings.compressor, true);
      // Vertical gestures over a band belong to the fader, so scroll the
      // page position to the dynamics group rather than editing another band.
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      tester.widget<AppLevelSlider>(attack).onChanged!(25);
      await tester.pumpAndSettle();
      expect(container.read(equalizerProvider).settings.attack, 25);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
