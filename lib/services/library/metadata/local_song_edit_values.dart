import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/utils/text/string_utils.dart';

/// The field values Edit Metadata shows for a song: the file's own tags where
/// they exist, otherwise the stored library row. Every save path (the editor
/// and the lyrics writer) builds its request from this one map, so a key that
/// one of them forgets cannot silently drop a tag.
Map<String, String> localSongEditValues(
  LocalLibraryItem item,
  Map<String, dynamic> tags,
) {
  String val(String key, Object? fallback) =>
      tags[key]?.toString() ?? fallback?.toString() ?? '';
  return <String, String>{
    'title': val('title', item.trackName),
    'artist': val('artist', item.artistName),
    'album': val('album', item.albumName),
    'album_artist': val('album_artist', item.albumArtist),
    'date': val('date', item.releaseDate),
    'track_number': val('track_number', item.trackNumber),
    'total_tracks': val('total_tracks', item.totalTracks),
    'disc_number': val('disc_number', item.discNumber),
    'total_discs': val('total_discs', item.totalDiscs),
    'genre': val('genre', item.genre),
    'isrc': val('isrc', item.isrc),
    'composer': val('composer', item.composer),
    'label': val('label', item.label),
    'copyright': val('copyright', item.copyright),
    'explicit': (parseExplicitFlag(tags['explicit']) ?? item.explicit)
        ? '1'
        : '0',
    for (final key in ['comment', 'album_type', 'upc', 'lyrics'])
      key: val(key, ''),
  };
}
