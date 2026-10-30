import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/utils/logging/log_entry.dart';
import 'package:sistrum/screens/settings/logs/log_entry_tile.dart';

LogEntry _entry({String level = 'INFO', bool fromGo = false, String? error}) =>
    LogEntry(
      timestamp: DateTime(2026, 1, 2, 3, 4, 5),
      level: level,
      tag: 'Player',
      message: 'Playback started',
      error: error,
      isFromGo: fromGo,
    );

Widget _tile(
  LogEntry entry, {
  bool selectionMode = false,
  bool selected = false,
  VoidCallback? onTap,
  VoidCallback? onLongPress,
}) => MaterialApp(
  home: Scaffold(
    body: LogEntryTile(
      entry: entry,
      levelColor: Colors.blue,
      selectionMode: selectionMode,
      selected: selected,
      onTap: onTap ?? () {},
      onLongPress: onLongPress ?? () {},
    ),
  ),
);

void main() {
  testWidgets('an entry shows its level, tag and message', (tester) async {
    await tester.pumpWidget(_tile(_entry()));
    expect(find.text('INFO'), findsOneWidget);
    expect(find.text('Player'), findsOneWidget);
    expect(find.textContaining('Playback started'), findsOneWidget);
    expect(find.text('Native'), findsNothing);
  });

  testWidgets('an entry from the native backend is marked as native', (
    tester,
  ) async {
    await tester.pumpWidget(_tile(_entry(fromGo: true)));
    expect(find.text('Native'), findsOneWidget);
  });

  testWidgets('an error entry shows its error text', (tester) async {
    await tester.pumpWidget(
      _tile(_entry(level: 'ERROR', error: 'Decoder failed')),
    );
    expect(find.text('ERROR'), findsOneWidget);
    expect(find.textContaining('Decoder failed'), findsOneWidget);
  });

  testWidgets('in selection mode a tap selects and shows the state icon', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _tile(
        _entry(),
        selectionMode: true,
        selected: false,
        onTap: () => taps++,
      ),
    );
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    await tester.tap(find.text('Player'));
    expect(taps, 1);
  });

  testWidgets('a selected entry shows the check icon', (tester) async {
    await tester.pumpWidget(
      _tile(_entry(), selectionMode: true, selected: true),
    );
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('a long press reports the entry for selection', (tester) async {
    var longPresses = 0;
    await tester.pumpWidget(_tile(_entry(), onLongPress: () => longPresses++));
    await tester.longPress(find.text('Player'));
    expect(longPresses, 1);
  });
}
