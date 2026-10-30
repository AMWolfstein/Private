import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/library/library_browse_rows.dart';

Map<String, dynamic> _row({
  Object? explicit = 0,
  Object? hasReplayGain = 0,
  Object? hasLyrics = 1,
  Object? replayGainVersion,
  String? source,
}) => {
  'queue_source': ?source,
  'id': 'song-1',
  'source_id': 'legacy',
  'explicit': explicit,
  'track_name': 'Song',
  'artist_name': 'Artist',
  'album_name': 'Album',
  'file_path': '/music/song.flac',
  'track_number': 2,
  'total_tracks': 9,
  'disc_number': 1,
  'total_discs': 1,
  'genre': 'Pop',
  'has_replaygain': hasReplayGain,
  'has_lyrics': hasLyrics,
  'replaygain_metadata_scan_version': ?replayGainVersion,
};

void main() {
  test('a browse row keeps its source and maps the track fields', () {
    final json = queueTrackRowToJson(_row(source: 'playlist'));
    expect(json['source'], 'playlist');
    final item = json['item'] as Map<String, dynamic>;
    expect(item['id'], 'song-1');
    expect(item['trackName'], 'Song');
    expect(item['artistName'], 'Artist');
    expect(item['trackNumber'], 2);
    expect(item['genre'], 'Pop');
    expect(item['filePath'], '/music/song.flac');
  });

  test('a row without a source is a local track', () {
    expect(queueTrackRowToJson(_row())['source'], 'local');
  });

  test('integer flags become booleans for explicit, ReplayGain and lyrics', () {
    final on = queueTrackRowToJson(
      _row(explicit: 1, hasReplayGain: 1, hasLyrics: 1),
    )['item'] as Map<String, dynamic>;
    expect(on['explicit'], isTrue);
    expect(on['hasReplayGain'], isTrue);
    expect(on['hasLyrics'], isTrue);

    final off = queueTrackRowToJson(
      _row(explicit: 0, hasReplayGain: 0, hasLyrics: 0),
    )['item'] as Map<String, dynamic>;
    expect(off['explicit'], isFalse);
    expect(off['hasReplayGain'], isFalse);
    expect(off['hasLyrics'], isFalse);
  });

  test('a missing ReplayGain scan version is zero', () {
    final item = queueTrackRowToJson(_row())['item'] as Map<String, dynamic>;
    expect(item['replayGainMetadataScanVersion'], 0);
  });
}
