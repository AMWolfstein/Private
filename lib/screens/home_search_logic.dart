import 'package:spotiflac_android/models/track.dart';

bool looksLikeUrlOrSpotifyUri(String text) =>
    text.startsWith('http') || text.startsWith('spotify:');

class HomeSearchResultBuckets {
  final List<Track> realTracks;
  final List<int> realTrackIndexes;
  final List<Track> albumItems;
  final List<Track> playlistItems;
  final List<Track> artistItems;

  const HomeSearchResultBuckets({
    required this.realTracks,
    required this.realTrackIndexes,
    required this.albumItems,
    required this.playlistItems,
    required this.artistItems,
  });
}

HomeSearchResultBuckets bucketHomeSearchResults(List<Track> tracks) {
  final realTracks = <Track>[];
  final realTrackIndexes = <int>[];
  final albumItems = <Track>[];
  final playlistItems = <Track>[];
  final artistItems = <Track>[];

  for (var index = 0; index < tracks.length; index++) {
    final track = tracks[index];
    if (!track.isCollection) {
      realTracks.add(track);
      realTrackIndexes.add(index);
    }
    if (track.isAlbumItem) albumItems.add(track);
    if (track.isPlaylistItem) playlistItems.add(track);
    if (track.isArtistItem) artistItems.add(track);
  }

  return HomeSearchResultBuckets(
    realTracks: realTracks,
    realTrackIndexes: realTrackIndexes,
    albumItems: albumItems,
    playlistItems: playlistItems,
    artistItems: artistItems,
  );
}

enum HomeSearchSortOption {
  defaultOrder,
  titleAsc,
  titleDesc,
  artistAsc,
  artistDesc,
  durationAsc,
  durationDesc,
  dateAsc,
  dateDesc,
}

List<T> sortHomeSearchItems<T>({
  required List<T> items,
  required HomeSearchSortOption option,
  required String Function(T) nameOf,
  required String Function(T) artistOf,
  required int Function(T) durationOf,
  required String? Function(T) dateOf,
}) {
  if (option == HomeSearchSortOption.defaultOrder) return items;

  final sorted = List<T>.of(items);
  switch (option) {
    case HomeSearchSortOption.defaultOrder:
      break;
    case HomeSearchSortOption.titleAsc:
      sorted.sort(
        (a, b) => nameOf(a).toLowerCase().compareTo(nameOf(b).toLowerCase()),
      );
    case HomeSearchSortOption.titleDesc:
      sorted.sort(
        (a, b) => nameOf(b).toLowerCase().compareTo(nameOf(a).toLowerCase()),
      );
    case HomeSearchSortOption.artistAsc:
      sorted.sort(
        (a, b) =>
            artistOf(a).toLowerCase().compareTo(artistOf(b).toLowerCase()),
      );
    case HomeSearchSortOption.artistDesc:
      sorted.sort(
        (a, b) =>
            artistOf(b).toLowerCase().compareTo(artistOf(a).toLowerCase()),
      );
    case HomeSearchSortOption.durationAsc:
      sorted.sort((a, b) => durationOf(a).compareTo(durationOf(b)));
    case HomeSearchSortOption.durationDesc:
      sorted.sort((a, b) => durationOf(b).compareTo(durationOf(a)));
    case HomeSearchSortOption.dateAsc:
      sorted.sort((a, b) => (dateOf(a) ?? '').compareTo(dateOf(b) ?? ''));
    case HomeSearchSortOption.dateDesc:
      sorted.sort((a, b) => (dateOf(b) ?? '').compareTo(dateOf(a) ?? ''));
  }
  return sorted;
}
