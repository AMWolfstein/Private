import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/controllers/metadata_editor_controller.dart';
import 'package:spotiflac_android/models/metadata_separators.dart';

void main() {
  test('save snapshots preserve empty tags and explicit track/disc totals', () {
    final editor = MetadataEditorController({
      'title': 'Song',
      'artist': 'Artist One; Artist Two',
      'total_tracks': '12',
      'total_discs': '2',
      'album_type': ' Compilation ',
      'explicit': 'true',
    });
    final tags = editor.saveMetadata(artistTagMode: 'all');
    editor['title']!.text = 'Changed';
    editor.dispose();

    expect(tags['title'], 'Song');
    expect(tags['artist'], 'Artist One; Artist Two');
    expect(tags['lyrics'], '');
    expect(tags['track_total'], '12');
    expect(tags['disc_total'], '2');
    expect(tags['compilation'], '1');
    expect(tags['explicit'], '1');
    expect(tags['artist_tag_mode'], 'all');
    expect(tags.containsKey('total_tracks'), isFalse);
    expect(tags.containsKey('total_discs'), isFalse);
  });

  test('save snapshots carry only the configured separators', () {
    final editor = MetadataEditorController({'artist': 'A, B'});
    final tags = editor.saveMetadata(
      artistTagMode: 'joined',
      separators: const MetadataSeparators(artist: ' / ', genre: '; '),
    );
    expect(tags['artist_separator'], ' / ');
    expect(tags['genre_separator'], '; ');
    expect(tags.containsKey('composer_separator'), isFalse);
    editor.dispose();
  });
}
