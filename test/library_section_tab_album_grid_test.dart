import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/screens/library/local_album_screen.dart';

import 'support/library_section_harness.dart';

void main() {
  setUp(
    () => installLibrarySongsDatabase(
      songs: const [],
      albums: const [(name: 'Blue Hour', artist: 'Ada', tracks: 9)],
    ),
  );

  testWidgets('an album card shows its title, artist and track count', (
    tester,
  ) async {
    await pumpLibrarySection(tester, section: 'albums');
    expect(find.text('Blue Hour'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping an album card opens the local album screen', (
    tester,
  ) async {
    await pumpLibrarySection(tester, section: 'albums');
    await tester.tap(find.text('Blue Hour'));
    await tester.pumpAndSettle();
    expect(find.byType(LocalAlbumScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
