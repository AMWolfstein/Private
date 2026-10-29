import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/models/local_library_item.dart';
import 'package:sistrum/services/library/library_edited_metadata.dart';

void main() {
  final item = LocalLibraryItem(
    id: 'stable-id',
    sourceId: 'sd-card',
    trackName: 'Old title',
    artistName: 'Artist',
    albumName: 'Album',
    filePath: 'content://music/file.flac',
    scannedAt: DateTime(2026),
    bitrate: 1200,
    bitDepth: 24,
    sampleRate: 96000,
    hasLyrics: true,
  );
  test(
    'edited tags refresh genre, explicit and numeric values without losing file identity',
    () {
      final json = localMetadataAfterEdit(item, {
        'title': 'New title',
        'genre': 'Jazz',
        'explicit': '1',
        'track_number': '3',
        'total_tracks': 12,
      });
      final edited = LocalLibraryItem.fromJson(json);
      expect(edited.trackName, 'New title');
      expect(edited.genre, 'Jazz');
      expect(edited.explicit, isTrue);
      expect(edited.trackNumber, 3);
      expect(edited.totalTracks, 12);
      expect(edited.sourceId, 'sd-card');
      expect(edited.id, item.id);
      expect(edited.filePath, item.filePath);
      expect(edited.bitrate, 1200);
      expect(edited.hasLyrics, isTrue);
    },
  );
  test('cleared lyrics and optional track values replace old tags', () {
    final edited = LocalLibraryItem.fromJson(
      localMetadataAfterEdit(item, {'lyrics': '', 'track_number': ''}),
    );
    expect(edited.hasLyrics, isFalse);
    expect(edited.trackNumber, isNull);
    expect(edited.artistName, item.artistName);
  });
}
