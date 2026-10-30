import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/sheets/app_audio_info_fact_rows.dart';
import 'package:sistrum/widgets/sheets/audio_info_facts.dart';

void main() {
  testWidgets('a fact row shows its label and value side by side', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        home: const Scaffold(
          body: AppAudioInfoFactGroup(
            children: [
              AppAudioInfoFactRow(
                fact: AudioInfoFact('Sample rate', '44.1 kHz'),
                last: true,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Sample rate'), findsOneWidget);
    expect(find.text('44.1 kHz'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a row has a divider unless it is the last one', (tester) async {
    Widget group({required bool last}) => MaterialApp(
      theme: AppTheme.build(Brightness.dark),
      home: Scaffold(
        body: AppAudioInfoFactGroup(
          children: [
            AppAudioInfoFactRow(
              fact: const AudioInfoFact('Codec', 'FLAC'),
              last: last,
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(group(last: false));
    expect(find.byType(Divider), findsOneWidget);
    await tester.pumpWidget(group(last: true));
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('a group places its rows in one card', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        home: const Scaffold(
          body: AppAudioInfoFactGroup(
            children: [
              AppAudioInfoFactRow(fact: AudioInfoFact('A', '1'), last: false),
              AppAudioInfoFactRow(fact: AudioInfoFact('B', '2'), last: true),
            ],
          ),
        ),
      ),
    );
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
  });
}
