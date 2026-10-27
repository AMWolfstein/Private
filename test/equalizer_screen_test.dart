import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/equalizer_provider.dart';
import 'package:sistrum/screens/equalizer_screen.dart';
import 'package:sistrum/services/playback_equalizer.dart';
import 'package:sistrum/models/equalizer_settings.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/widgets/sistrum_level_slider.dart';

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
              theme: SistrumTheme.build(brightness),
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
              (widget) => widget is SistrumLevelSlider && widget.vertical,
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
}
