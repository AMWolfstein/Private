import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/models/library_collections.dart';
import 'package:sistrum/widgets/sheets/playlist_picker_rows.dart';

PlaylistPickerSummary _playlist({String? cover, String? preview}) =>
    PlaylistPickerSummary(
      id: 'p',
      name: 'Road trip',
      coverImagePath: cover,
      previewCover: preview,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      trackCount: 4,
      containsAllRequestedTracks: false,
    );

void main() {
  testWidgets('a picker row shows its title, subtitle and selection state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlaylistPickerRow(
            leading: Icon(Icons.queue_music),
            title: Text('Road trip'),
            subtitle: Text('4 tracks'),
            selected: true,
          ),
        ),
      ),
    );
    expect(find.text('Road trip'), findsOneWidget);
    expect(find.text('4 tracks'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.checkmark_circle_fill), findsOneWidget);
  });

  testWidgets('an unselected row shows an empty circle', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlaylistPickerRow(
            leading: Icon(Icons.queue_music),
            title: Text('Road trip'),
            selected: false,
          ),
        ),
      ),
    );
    expect(find.byIcon(CupertinoIcons.circle), findsOneWidget);
  });

  testWidgets('a disabled row does not respond to taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaylistPickerRow(
            leading: const Icon(Icons.queue_music),
            title: const Text('Road trip'),
            enabled: false,
            onTap: () => taps++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Road trip'));
    expect(taps, 0);
  });

  testWidgets('an enabled row reports its taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaylistPickerRow(
            leading: const Icon(Icons.queue_music),
            title: const Text('Road trip'),
            onTap: () => taps++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Road trip'));
    expect(taps, 1);
  });

  testWidgets('a thumbnail with no cover shows the playlist icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaylistPickerThumbnail(
            playlist: _playlist(),
            isSelected: false,
          ),
        ),
      ),
    );
    expect(find.byIcon(CupertinoIcons.music_note_list), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('a selected thumbnail shows a check mark', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaylistPickerThumbnail(
            playlist: _playlist(),
            isSelected: true,
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
