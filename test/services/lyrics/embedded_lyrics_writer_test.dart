import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/services/library/metadata/metadata_edit_result.dart';
import 'package:sistrum/services/library/metadata/track_metadata_persistence.dart';
import 'package:sistrum/services/lyrics/embedded_lyrics_writer.dart';

LocalLibraryItem _song() => LocalLibraryItem(
  id: 'song-1',
  sourceId: 'legacy',
  trackName: 'Song',
  artistName: 'Artist',
  albumName: 'Album',
  filePath: '/music/song.flac',
  scannedAt: DateTime(2026),
  genre: 'Rock',
  duration: 200,
);

void main() {
  test(
    'the lyrics write keeps the file tags that were already there',
    () async {
      Map<String, String>? sent;
      final store = MetadataEmbeddedLyricsStore(
        readTags: (_) async => {
          'title': 'Song From File',
          'genre': 'Folk',
          'lyrics': '',
        },
        persistence: (covers) => MetadataPersistenceService(
          covers: covers,
          edit: (path, metadata) async {
            sent = metadata;
            return MetadataEditResult.decode({'method': 'native'});
          },
          read: (_) async => {},
        ),
      );

      final result = await store.write(_song(), '[00:01.00]Hi');

      expect(result.saved, isTrue);
      expect(sent!['lyrics'], '[00:01.00]Hi');
      expect(sent!['title'], 'Song From File');
      expect(sent!['genre'], 'Folk');
      expect(sent!['artist'], 'Artist');
    },
  );

  test('a failed edit is reported with its failure kind', () async {
    final store = MetadataEmbeddedLyricsStore(
      readTags: (_) async => {},
      persistence: (covers) => MetadataPersistenceService(
        covers: covers,
        edit: (path, metadata) async =>
            MetadataEditResult.decode({'error': 'disk full'}),
        read: (_) async => {},
      ),
    );

    final result = await store.write(_song(), '[00:01.00]Hi');

    expect(result.saved, isFalse);
    expect(result.failure, MetadataSaveFailure.backend);
  });

  test('a failed index refresh does not undo a saved file', () async {
    final store = MetadataEmbeddedLyricsStore(
      readTags: (_) async => {},
      persistence: (covers) => MetadataPersistenceService(
        covers: covers,
        edit: (path, metadata) async =>
            MetadataEditResult.decode({'method': 'native'}),
        read: (_) async => {},
      ),
      refreshIndex: (_) async => throw StateError('index busy'),
    );

    final result = await store.write(_song(), '[00:01.00]Hi');

    expect(result.saved, isTrue);
  });
}
