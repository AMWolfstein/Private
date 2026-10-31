import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/providers/library/library_browse_provider.dart';

import '../../support/home_tab_harness.dart';

void main() {
  testWidgets('a release without artwork shows the album fallback icon', (
    tester,
  ) async {
    await pumpHome(
      tester,
      loader: (request) async =>
          LibraryBrowsePage([bareRelease('No Art Album')]),
    );
    expect(find.text('No Art Album'), findsWidgets);
    expect(find.byIcon(Icons.album_outlined), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
