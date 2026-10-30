import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/providers/metadata_editor_controller.dart';
import 'package:sistrum/core/models/metadata_separators.dart';
import 'package:sistrum/services/library/browse/library_tag_credits.dart';

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
    final tags = editor.buildMetadataTags();
    editor['title']!.text = 'Changed';
    editor.dispose();

    expect(tags['title'], 'Song');
    expect(tags['artist'], 'Artist One; Artist Two');
    expect(tags['lyrics'], '');
    expect(tags['track_total'], '12');
    expect(tags['disc_total'], '2');
    expect(tags['compilation'], '1');
    expect(tags['explicit'], '1');
    expect(tags.containsKey('total_tracks'), isFalse);
    expect(tags.containsKey('total_discs'), isFalse);
  });

  test('save joins name fields with the Save with separator, no keys', () {
    final editor = MetadataEditorController({
      'artist': 'A, B',
      'genre': 'Rock; Pop',
    });
    final tags = editor.buildMetadataTags(
      separators: const MetadataSeparators(artist: ' / ', genre: '; '),
    );
    expect(tags['artist'], 'A / B');
    expect(tags['genre'], 'Rock; Pop');
    expect(tags.keys.where((key) => key.endsWith('_separator')), isEmpty);
    editor.dispose();
  });

  test('a keep together name is not split when it is saved', () {
    final editor = MetadataEditorController({
      'artist': 'Tyler, The Creator, Kali Uchis',
    });
    final tags = editor.buildMetadataTags(
      separators: const MetadataSeparators(artist: ' / '),
      rules: const TagCreditRules(keepTogether: ['Tyler, The Creator']),
    );
    expect(tags['artist'], 'Tyler, The Creator / Kali Uchis');
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
    final tags = editor.buildMetadataTags(onlyChanged: true);

    expect(tags['title'], 'Changed');
    expect(tags.containsKey('lyrics'), isFalse);
    expect(tags.containsKey('comment'), isFalse);
    expect(tags.containsKey('album_type'), isFalse);
    expect(tags.containsKey('upc'), isFalse);
    expect(tags.containsKey('artist'), isFalse);
    editor.dispose();
  });

  test('onlyChanged sends an explicitly cleared field as empty', () {
    final editor = MetadataEditorController({
      'title': 'Song',
      'lyrics': 'Old lyrics',
    });
    editor['lyrics']!.text = '';
    final tags = editor.buildMetadataTags(onlyChanged: true);

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
    final tags = editor.buildMetadataTags(onlyChanged: true);

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
    final tags = editor.buildMetadataTags(onlyChanged: true);

    expect(tags['track_number'], '3');
    expect(tags['track_total'], '13');
    expect(tags['disc_number'], '1');
    expect(tags['disc_total'], '3');
    editor.dispose();
  });
}
