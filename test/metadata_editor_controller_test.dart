import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/controllers/metadata_editor_controller.dart';
import 'package:sistrum/models/metadata_separators.dart';

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
    final tags = editor.saveMetadata();
    editor['title']!.text = 'Changed';
    editor.dispose();

    expect(tags['title'], 'Song');
    expect(tags['artist'], 'Artist One; Artist Two');
    expect(tags['lyrics'], '');
    expect(tags['track_total'], '12');
    expect(tags['disc_total'], '2');
    expect(tags['compilation'], '1');
    expect(tags['explicit'], '1');
    expect(tags['artist_tag_mode'], 'joined');
    expect(tags.containsKey('total_tracks'), isFalse);
    expect(tags.containsKey('total_discs'), isFalse);
  });

  test('save snapshots carry only the configured separators', () {
    final editor = MetadataEditorController({'artist': 'A, B'});
    final tags = editor.saveMetadata(
      separators: const MetadataSeparators(artist: ' / ', genre: '; '),
    );
    expect(tags['artist_separator'], ' / ');
    expect(tags['genre_separator'], '; ');
    expect(tags.containsKey('composer_separator'), isFalse);
    editor.dispose();
  });

  test('onlyChanged omits tags the prefill could not read', () {
    final editor = MetadataEditorController({
      'title': 'Song',
      'artist': 'Artist',
      'lyrics': '',
      'comment': '',
      'album_type': '',
      'upc': '',
    });
    editor['title']!.text = 'Changed';
    final tags = editor.saveMetadata(onlyChanged: true);

    expect(tags['title'], 'Changed');
    expect(tags.containsKey('lyrics'), isFalse);
    expect(tags.containsKey('comment'), isFalse);
    expect(tags.containsKey('album_type'), isFalse);
    expect(tags.containsKey('upc'), isFalse);
    expect(tags.containsKey('artist'), isFalse);
    expect(tags['artist_tag_mode'], 'joined');
    editor.dispose();
  });

  test('onlyChanged sends an explicitly cleared field as empty', () {
    final editor = MetadataEditorController({
      'title': 'Song',
      'lyrics': 'Old lyrics',
    });
    editor['lyrics']!.text = '';
    final tags = editor.saveMetadata(onlyChanged: true);

    expect(tags['lyrics'], '');
    expect(tags.containsKey('title'), isFalse);
    editor.dispose();
  });

  test('onlyChanged keeps derived totals, compilation and explicit', () {
    final editor = MetadataEditorController({
      'album_type': 'Album',
      'total_tracks': '3',
      'explicit': 'false',
    });
    editor['album_type']!.text = 'Compilation';
    editor['total_tracks']!.text = '12';
    editor.explicit = true;
    final tags = editor.saveMetadata(onlyChanged: true);

    expect(tags['album_type'], 'Compilation');
    expect(tags['compilation'], '1');
    expect(tags['track_total'], '12');
    expect(tags['explicit'], '1');
    expect(tags.containsKey('title'), isFalse);
    editor.dispose();
  });

  test('onlyChanged keeps the current number when its total changes', () {
    final editor = MetadataEditorController({
      'track_number': '3',
      'total_tracks': '12',
      'disc_number': '1',
      'total_discs': '2',
    });
    editor['total_tracks']!.text = '13';
    editor['total_discs']!.text = '3';
    final tags = editor.saveMetadata(onlyChanged: true);

    expect(tags['track_number'], '3');
    expect(tags['track_total'], '13');
    expect(tags['disc_number'], '1');
    expect(tags['disc_total'], '3');
    editor.dispose();
  });
}
