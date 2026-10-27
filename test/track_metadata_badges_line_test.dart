import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/widgets/audio_quality_badges.dart';

void main() {
  testWidgets('track metadata badges wrap on a narrow result row', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            child: SizedBox(
              width: 180,
              child: Builder(
                builder: (context) {
                  final colorScheme = Theme.of(context).colorScheme;
                  return TrackMetadataBadgesLine(
                    primary: const Text(
                      'RADWIMPS',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    badges: [
                      AudioQualityBadge(
                        label: '16-bit',
                        colorScheme: colorScheme,
                      ),
                      AudioQualityBadge(
                        label: '96 kHz',
                        colorScheme: colorScheme,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.text('96 kHz')).dy,
      greaterThan(tester.getTopLeft(find.text('RADWIMPS')).dy),
    );
  });
}
