/// Pure metadata-key conversion used by the different audio containers.
///
/// Keeping these mappings independent from FFmpeg execution makes the tag
/// contract directly testable and prevents container-specific policy from
/// being buried in the conversion orchestration.
class AudioMetadataMapper {
  const AudioMetadataMapper._();

  /// Normalizes arbitrary tag spellings to standard Vorbis comment names.
  static Map<String, String> normalizeToVorbisComments(
    Map<String, String> metadata,
  ) {
    final vorbis = <String, String>{};

    for (final entry in metadata.entries) {
      final key = _normalizeKey(entry.key);
      final value = entry.value;

      switch (key) {
        case 'TITLE':
          vorbis['TITLE'] = value;
        case 'ARTIST':
          vorbis['ARTIST'] = value;
        case 'ALBUM':
          vorbis['ALBUM'] = value;
        case 'ALBUMARTIST':
          vorbis['ALBUMARTIST'] = value;
        case 'TRACKNUMBER':
        case 'TRACKNBR':
        case 'TRACK':
        case 'TRCK':
          if (value != '0') vorbis['TRACKNUMBER'] = value;
        case 'DISCNUMBER':
        case 'DISC':
        case 'TPOS':
          if (value != '0') vorbis['DISCNUMBER'] = value;
        case 'DATE':
          vorbis['DATE'] = value;
          final yearMatch = RegExp(r'^(\d{4})').firstMatch(value);
          if (yearMatch != null &&
              (!vorbis.containsKey('YEAR') || vorbis['YEAR']!.isEmpty)) {
            vorbis['YEAR'] = yearMatch.group(1)!;
          }
        case 'YEAR':
          vorbis['YEAR'] = value;
          if (!vorbis.containsKey('DATE') || vorbis['DATE']!.isEmpty) {
            vorbis['DATE'] = value;
          }
        case 'GENRE':
          vorbis['GENRE'] = value;
        case 'ISRC':
          vorbis['ISRC'] = value;
        case 'LABEL':
        case 'ORGANIZATION':
          vorbis['ORGANIZATION'] = value;
        case 'COPYRIGHT':
          vorbis['COPYRIGHT'] = value;
        case 'COMPOSER':
          vorbis['COMPOSER'] = value;
        case 'COMMENT':
          vorbis['COMMENT'] = value;
        case 'ITUNESADVISORY':
        case 'EXPLICIT':
        case 'ISEXPLICIT':
          vorbis['ITUNESADVISORY'] = _normalizeAdvisoryValue(value);
        case 'LYRICS':
        case 'UNSYNCEDLYRICS':
          vorbis['LYRICS'] = value;
          vorbis['UNSYNCEDLYRICS'] = value;
        case 'REPLAYGAINTRACKGAIN':
          vorbis['REPLAYGAIN_TRACK_GAIN'] = value;
        case 'REPLAYGAINTRACKPEAK':
          vorbis['REPLAYGAIN_TRACK_PEAK'] = value;
        case 'REPLAYGAINALBUMGAIN':
          vorbis['REPLAYGAIN_ALBUM_GAIN'] = value;
        case 'REPLAYGAINALBUMPEAK':
          vorbis['REPLAYGAIN_ALBUM_PEAK'] = value;
        case 'R128TRACKGAIN':
          vorbis['R128_TRACK_GAIN'] = value;
        case 'R128ALBUMGAIN':
          vorbis['R128_ALBUM_GAIN'] = value;
      }
    }

    return vorbis;
  }

  static void appendVorbisMetadataArguments(
    List<String> arguments,
    Map<String, String> metadata,
  ) {
    for (final entry in buildVorbisMetadataEntries(metadata)) {
      arguments
        ..add('-metadata')
        ..add('${entry.key}=${entry.value}');
    }
  }

  static void appendMappedMetadataArguments(
    List<String> arguments,
    Map<String, String> metadata,
  ) {
    for (final entry in metadata.entries) {
      arguments
        ..add('-metadata')
        ..add('${entry.key}=${entry.value}');
    }
  }

  static List<MapEntry<String, String>> buildVorbisMetadataEntries(
    Map<String, String> metadata,
  ) {
    final vorbis = normalizeToVorbisComments(metadata);
    final entries = <MapEntry<String, String>>[];

    for (final entry in vorbis.entries) {
      if (entry.key == 'ARTIST' || entry.key == 'ALBUMARTIST') {
        continue;
      }
      entries.add(entry);
    }

    _appendVorbisArtistEntries(entries, 'ARTIST', vorbis['ARTIST']);
    _appendVorbisArtistEntries(entries, 'ALBUMARTIST', vorbis['ALBUMARTIST']);

    return entries;
  }

  static void _appendVorbisArtistEntries(
    List<MapEntry<String, String>> entries,
    String key,
    String? rawValue,
  ) {
    if (rawValue == null) return;
    final value = rawValue.trim();
    // An empty entry is preserved so FFmpeg clears an existing tag.
    entries.add(MapEntry(key, value));
  }

  static String _normalizeKey(String key) =>
      key.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static String _normalizeAdvisoryValue(String value) {
    return switch (value.trim().toLowerCase()) {
      'true' || 'yes' || 'explicit' => '1',
      'false' || 'no' => '0',
      final value => value,
    };
  }
}
