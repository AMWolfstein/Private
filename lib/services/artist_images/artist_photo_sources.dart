import 'package:http/http.dart' as http;
import 'package:sistrum/services/animated_artwork/apple_artwork_client.dart';
import 'package:sistrum/services/animated_artwork/apple_artwork_parse.dart';
import 'package:sistrum/services/artist_images/deezer_artist_search.dart';

/// Where an artist photo came from.
enum ArtistPhotoSource { apple, deezer }

/// One artist that a photo search offers. [pictureUrl] is null when the source
/// has the artist but no portrait for them.
class ArtistPhotoCandidate {
  const ArtistPhotoCandidate({
    required this.name,
    required this.source,
    this.pictureUrl,
    this.deezerId,
    this.fans,
    this.albums,
  });

  final String name;
  final ArtistPhotoSource source;
  final String? pictureUrl;

  /// Deezer's artist id, kept with the record. Null for Apple matches.
  final int? deezerId;
  final int? fans;
  final int? albums;
}

/// Deezer artists for [name], as photo candidates.
Future<List<ArtistPhotoCandidate>> deezerPhotoCandidates(
  http.Client client,
  String name,
) async {
  final artists = await DeezerArtistSearch(client).search(name);
  return [
    for (final artist in artists)
      ArtistPhotoCandidate(
        name: artist.name,
        source: ArtistPhotoSource.deezer,
        pictureUrl: artist.pictureUrl,
        deezerId: artist.id,
        fans: artist.fans,
        albums: artist.albums,
      ),
  ];
}

/// Apple Music artists for [name], as photo candidates. Throws
/// [AppleArtworkUnavailable] when the catalog cannot answer.
Future<List<ArtistPhotoCandidate>> applePhotoCandidates(
  AppleArtworkClient api,
  String name,
) async {
  final found = await api.search(name);
  return [
    for (final item in found)
      if (item.kind == AppleArtworkKind.artist)
        ArtistPhotoCandidate(
          name: item.name,
          source: ArtistPhotoSource.apple,
          pictureUrl: item.previewUrl,
        ),
  ];
}
