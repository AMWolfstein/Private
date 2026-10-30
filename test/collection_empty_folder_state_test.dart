import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/screens/library/collections/collection_empty_folder_state.dart';

void main() {
  testWidgets('an empty folder shows its title, subtitle and folder icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CollectionEmptyFolderState(
            title: 'Nothing here',
            subtitle: 'Add music to fill this folder',
          ),
        ),
      ),
    );
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('Add music to fill this folder'), findsOneWidget);
    expect(find.byIcon(Icons.folder_open), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
