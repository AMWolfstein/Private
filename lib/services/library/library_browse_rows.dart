Map<String, dynamic> queueTrackRowToJson(Map<String, dynamic> row) {
  final source = row['queue_source'] as String? ?? 'local';
  final item = <String, dynamic>{
    'id': row['id'],
    'sourceId': row['source_id'],
    'explicit': row['explicit'] == 1 || row['explicit'] == true,
    'trackName': row['track_name'],
    'artistName': row['artist_name'],
    'albumName': row['album_name'],
    'albumArtist': row['album_artist'],
    'filePath': row['file_path'],
    'fileSize': row['file_size_bytes'],
    'isrc': row['isrc'],
    'trackNumber': row['track_number'],
    'totalTracks': row['total_tracks'],
    'discNumber': row['disc_number'],
    'totalDiscs': row['total_discs'],
    'duration': row['duration'],
    'releaseDate': row['release_date'],
    'bitDepth': row['bit_depth'],
    'sampleRate': row['sample_rate'],
    'bitrate': row['bitrate'],
    'format': row['format'],
    'hasReplayGain':
        row['has_replaygain'] == 1 || row['has_replaygain'] == true,
    'genre': row['genre'],
    'composer': row['composer'],
    'label': row['label'],
    'copyright': row['copyright'],
    'coverUrl': row['cover_url'],
    'coverPath': row['cover_path'],
    'scannedAt': row['scanned_at'],
    'fileModTime': row['file_mod_time'],
    'quality': row['quality'],
    'replayGainMetadataScanVersion':
        row['replaygain_metadata_scan_version'] ?? 0,
  };
  return {'source': source, 'item': item};
}
