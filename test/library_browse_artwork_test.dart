import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/providers/library_browse_provider.dart';
import 'package:sistrum/screens/library/library_browse_artwork.dart';

void main() {
  testWidgets('an entry without artwork shows the album fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 120,
            child: LibraryBrowseArtwork(
              entry: LibraryBrowseEntry(
                source: 'local',
                key: 'album',
                name: 'Album',
                artist: 'Artist',
                samplePath: '',
                trackCount: 3,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.album_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
