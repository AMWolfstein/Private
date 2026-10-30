import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/screens/library/artist_song_pages.dart';

Widget _pages(int count) => MaterialApp(
  home: Scaffold(
    body: ArtistSongPages(
      itemCount: count,
      itemBuilder: (_, index) =>
          SizedBox(height: 64, child: Text('Song $index')),
    ),
  ),
);

void main() {
  testWidgets('the first page shows the first five songs', (tester) async {
    await tester.pumpWidget(_pages(12));
    await tester.pumpAndSettle();
    expect(find.text('Song 0'), findsOneWidget);
    expect(find.text('Song 4'), findsOneWidget);
    expect(find.text('Song 5'), findsNothing);
  });

  testWidgets('twelve songs make three pages with one dot each', (
    tester,
  ) async {
    await tester.pumpWidget(_pages(12));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('artist-popular-dot-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('artist-popular-dot-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('artist-popular-dot-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('artist-popular-dot-3')), findsNothing);
  });

  testWidgets('tapping a dot moves to that page of songs', (tester) async {
    await tester.pumpWidget(_pages(12));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('artist-popular-dot-1')));
    await tester.pumpAndSettle();
    expect(find.text('Song 5'), findsOneWidget);
    expect(find.text('Song 0'), findsNothing);
  });

  testWidgets('a short list has no page dots', (tester) async {
    await tester.pumpWidget(_pages(3));
    await tester.pumpAndSettle();
    expect(find.text('Song 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('artist-popular-dot-0')), findsNothing);
  });
}
