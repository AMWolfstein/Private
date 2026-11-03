import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/providers/animated_artwork/animated_artwork_providers.dart';
import 'package:sistrum/services/animated_artwork/animated_artwork_store.dart';
import 'package:sistrum/services/library/browse/library_tag_credits.dart';

LocalLibraryItem _track({
  required String id,
  required String artist,
  required String album,
  String? albumArtist,
  int? totalTracks,
}) => LocalLibraryItem(
  id: id,
  trackName: 'Track $id',
  artistName: artist,
  albumName: album,
  albumArtist: albumArtist,
  filePath: '/music/$id.flac',
  scannedAt: DateTime.utc(2026),
  totalTracks: totalTracks,
);

Map<String, dynamic> _row(LocalLibraryItem item) => item.toJson();

void main() {
  group('album identity shared by every track', () {
    test('two tracks of one album resolve to the same reference', () {
      final first = _track(id: '1', artist: 'Nina', album: 'Pastel Blues', albumArtist: 'Nina Simone');
      final second = _track(id: '2', artist: 'Nina Simone', album: 'Pastel Blues', albumArtist: 'Nina Simone');
      expect(animatedAlbumRefForItem(first), animatedAlbumRefForItem(second));
    });

    test('the album detail page and Now Playing use the same key', () {
      // The album screen is given the title and the album artist, which is
      // what the track row resolves to.
      final item = _track(id: '1', artist: 'Feature Artist', album: 'Live', albumArtist: 'Band');
      expect(
        animatedAlbumRefForItem(item),
        animatedAlbumRef('Live', 'Band'),
      );
    });

    test('a track without an album artist falls back to its artist', () {
      final item = _track(id: '1', artist: 'Band', album: 'Live');
      expect(animatedAlbumRefForItem(item), animatedAlbumRef('Live', 'Band'));
    });

    test('a deluxe edition is a different album', () {
      final standard = animatedAlbumRef('Abbey Road', 'The Beatles');
      final deluxe = animatedAlbumRef('Abbey Road (Deluxe)', 'The Beatles');
      expect(standard, isNot(deluxe));
    });

    test('an album and an artist with the same name never share a record', () {
      final album = animatedAlbumRef('Nina', 'Nina');
      final artist = animatedArtistRef('Nina');
      expect(animatedArtworkId(album.kind, album.key),
          isNot(animatedArtworkId(artist.kind, artist.key)));
    });
  });

  group('lookup targets from the library', () {
    final rules = const TagCreditRules();

    test('albums are listed once, albums first, then artists', () async {
      final songs = [
        _row(_track(id: '1', artist: 'Band', album: 'One', totalTracks: 10)),
        _row(_track(id: '2', artist: 'Band', album: 'One', totalTracks: 10)),
        _row(_track(id: '3', artist: 'Solo', album: 'Two')),
      ];
      final targets = await animatedArtworkTargets(songs: songs, rules: rules);

      expect(targets.map((t) => t.kind), [
        AnimatedArtworkKind.album,
        AnimatedArtworkKind.album,
        AnimatedArtworkKind.artist,
        AnimatedArtworkKind.artist,
      ]);
      expect(targets.first.title, 'One');
      expect(targets.first.trackCount, 10);
    });

    test('Various Artists and unknown artists are never looked up', () async {
      final songs = [
        _row(_track(id: '1', artist: 'Band', album: 'Mix', albumArtist: 'Various Artists')),
        _row(_track(id: '2', artist: 'Unknown artist', album: 'Other')),
      ];
      final targets = await animatedArtworkTargets(songs: songs, rules: rules);
      expect(targets.where((t) => t.kind == AnimatedArtworkKind.album), isEmpty);
      expect(
        targets.where((t) => t.kind == AnimatedArtworkKind.artist).map((t) => t.artistName),
        ['Band'],
      );
    });

    test('a credit that is split into names gives each name its own target', () async {
      final songs = [
        _row(_track(id: '1', artist: 'Alpha & Beta', album: 'Joint')),
      ];
      final targets = await animatedArtworkTargets(songs: songs, rules: rules);
      final names = targets
          .where((t) => t.kind == AnimatedArtworkKind.artist)
          .map((t) => t.artistName)
          .toList();
      expect(names, containsAll(['Alpha', 'Beta']));
    });
  });
}
