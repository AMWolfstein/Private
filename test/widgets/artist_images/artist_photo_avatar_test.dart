import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/artist_images/find_artist_image_sheet.dart';

void main() {
  testWidgets('a Deezer picture is loaded as a network image', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ArtistPhotoAvatar(url: 'https://cdn.example.test/akon.jpg'),
        ),
      ),
    );
    final photo = find.byWidgetPredicate(
      (widget) => widget is Image && widget.image is NetworkImage,
    );
    expect(photo, findsOneWidget);
    expect(
      (tester.widget<Image>(photo).image as NetworkImage).url,
      'https://cdn.example.test/akon.jpg',
    );
    expect(find.byType(CircleAvatar), findsNothing);
  });

  testWidgets('an artist without a picture shows the placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ArtistPhotoAvatar(url: null)),
      ),
    );
    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
