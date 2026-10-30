import 'package:sistrum/models/local_library_item.dart';
import 'package:sistrum/utils/text/string_utils.dart';

/// Refresh editable tags while retaining the scanned file identity and audio facts.
Map<String, dynamic> localMetadataAfterEdit(
  LocalLibraryItem item,
  Map<String, dynamic> tags,
) {
  final json = item.toJson();
  const text = {
    'title': 'trackName',
    'artist': 'artistName',
    'album': 'albumName',
    'album_artist': 'albumArtist',
    'date': 'releaseDate',
    'genre': 'genre',
    'isrc': 'isrc',
    'composer': 'composer',
    'label': 'label',
    'copyright': 'copyright',
  };
  const numbers = {
    'track_number': 'trackNumber',
    'total_tracks': 'totalTracks',
    'disc_number': 'discNumber',
    'total_discs': 'totalDiscs',
  };
  for (final field in text.entries) {
    if (tags.containsKey(field.key)) {
      json[field.value] = tags[field.key]?.toString() ?? '';
    }
  }
  for (final field in numbers.entries) {
    if (tags.containsKey(field.key)) {
      json[field.value] = int.tryParse(tags[field.key]?.toString() ?? '');
    }
  }
  json['explicit'] = parseExplicitFlag(tags['explicit']) ?? item.explicit;
  if (tags.containsKey('lyrics')) {
    json['hasLyrics'] = tags['lyrics']?.toString().trim().isNotEmpty ?? false;
  }
  return json;
}
