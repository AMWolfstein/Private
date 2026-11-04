import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/core/models/theme_settings.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/settings/theme_provider.dart';
import 'package:sistrum/utils/lyrics/lyric_models.dart';
import 'package:sistrum/widgets/lyrics/app_lyrics_timing_setting.dart';
import 'package:g1455/g1455.dart' show GlassSlider;

void main() {
  test(
    'offset preserves original timing and shifts all vocal layers together',
    () {
      const line = LyricLine(
        time: Duration(seconds: 1),
        end: Duration(seconds: 3),
        text: 'Hello',
        words: [
          LyricWord(
            time: Duration(seconds: 1),
            end: Duration(seconds: 2),
            text: 'Hello',
          ),
        ],
        romanizationWords: [
          LyricWord(time: Duration(seconds: 1), text: 'Halo'),
        ],
        translation: 'Hi',
        isBackground: true,
        vocalGroup: 7,
      );
      final shifted = offsetLyricLine(
        line,
        const Duration(milliseconds: -2000),
      );
      expect(shifted.time, const Duration(seconds: -1));
      expect(shifted.words.first.end, Duration.zero);
      expect(shifted.romanizationWords.first.time, const Duration(seconds: -1));
      expect(shifted.vocalGroup, 7);
      expect(shifted.isBackground, true);
      expect(
        offsetLyricLine(shifted, const Duration(seconds: 2)).time,
        line.time,
      );
      expect(line.time, const Duration(seconds: 1));
      expect(normalizeLyricsTimingOffset(double.nan), 0);
      expect(normalizeLyricsTimingOffset(10000), 2000);
      expect(normalizeLyricsTimingOffset(-10000), -2000);
      final settings = const ThemeSettings().copyWith(
        lyricsTimingOffsetMs: 500,
      );
      expect(ThemeSettings.fromJson(settings.toJson()), settings);
      expect(ThemeSettings.fromJson({}).lyricsTimingOffsetMs, 0);
    },
  );
  testWidgets(
    'offset previews without saving, persists on release and resets',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: AppLyricsTimingSetting()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final slider = tester.widget<GlassSlider>(find.byType(GlassSlider));
      slider.onChanged!((500 + 2000) / 4000);
      await tester.pump();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(kLyricsTimingOffsetKey), isNull);
      expect(container.read(themeProvider).lyricsTimingOffsetMs, 500);
      slider.onChangeEnd!((500 + 2000) / 4000);
      await tester.pumpAndSettle();
      expect(loadBootstrapThemeSettings(prefs).lyricsTimingOffsetMs, 500);
      await tester.tap(find.byTooltip('Reset'));
      await tester.pumpAndSettle();
      expect(loadBootstrapThemeSettings(prefs).lyricsTimingOffsetMs, 0);
    },
  );
}
