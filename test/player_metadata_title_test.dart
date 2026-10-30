import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/providers/player_metadata_controller.dart';
import 'package:sistrum/widgets/player/player_metadata_title.dart';

void main() {
  testWidgets('the title shows the current track name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerMetadataTitle(
            mediaItem: const MediaItem(id: 'a', title: 'Blue Hour'),
            metadata: PlayerMetadataController(
              readMetadata: (_, {displayName}) async => {},
              parseLyrics: (_) async => throw UnimplementedError(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Blue Hour'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
