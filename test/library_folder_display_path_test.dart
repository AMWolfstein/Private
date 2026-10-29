import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/library/library_folder_selection.dart';

void main() {
  group('libraryFolderDisplayPath', () {
    test('leaves plain filesystem paths unchanged', () {
      expect(
        libraryFolderDisplayPath('/storage/emulated/0/Music'),
        '/storage/emulated/0/Music',
      );
    });

    test('maps the primary SAF volume to its emulated path', () {
      expect(
        libraryFolderDisplayPath(
          'content://com.android.externalstorage.documents/tree/primary%3AMusic',
        ),
        '/storage/emulated/0/Music',
      );
    });

    test('shows other SAF folder names decoded', () {
      expect(
        libraryFolderDisplayPath(
          'content://com.android.externalstorage.documents/tree/Music%20Box',
        ),
        'Music Box',
      );
      expect(
        libraryFolderDisplayPath(
          'content://com.android.externalstorage.documents/tree/sd%3A1234%3AAlbums',
        ),
        'sd:1234:Albums',
      );
    });

    test('does not decode a literal percent sequence twice', () {
      expect(
        libraryFolderDisplayPath(
          'content://com.android.externalstorage.documents/tree/100%2525',
        ),
        '100%25',
      );
    });
  });
}
