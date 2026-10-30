import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/models/track.dart';
import 'package:sistrum/services/library/collections/m3u_playlist_service.dart';

void main() {
  group('buildM3u8Content', () {
    test('writes EXTM3U header and EXTINF entries', () {
      final content = M3uPlaylistService.buildM3u8Content([
        M3uExportEntry(
          track: Track(
            id: 't1',
            name: 'Song',
            artistName: 'Artist',
            albumName: 'Album',
            duration: 200,
            coverUrl: null,
          ),
          path: 'Artist/Album/Song.flac',
        ),
      ]);

      expect(
        content,
        '#EXTM3U\n#EXTINF:200,Artist - Song\nArtist/Album/Song.flac\n',
      );
    });
  });

  group('exportPathFor', () {
    test('passes plain paths through', () {
      expect(
        M3uPlaylistService.exportPathFor('/storage/emulated/0/Music/a.flac'),
        '/storage/emulated/0/Music/a.flac',
      );
    });

    test('makes SAF document URIs relative to their tree root', () {
      expect(
        M3uPlaylistService.exportPathFor(
          'content://com.android.externalstorage.documents/tree/'
          'primary%3AMusic/document/'
          'primary%3AMusic%2FArtist%2FAlbum%2Fsong.flac',
        ),
        'Artist/Album/song.flac',
      );
    });

    test('strips the storage prefix without tree context', () {
      expect(
        M3uPlaylistService.exportPathFor(
          'content://com.android.externalstorage.documents/document/'
          'primary%3AMusic%2Fsong.flac',
        ),
        'Music/song.flac',
      );
    });

    test('returns null for content URIs without a document path', () {
      expect(
        M3uPlaylistService.exportPathFor('content://media/external/audio/1'),
        isNull,
      );
    });
  });
}
