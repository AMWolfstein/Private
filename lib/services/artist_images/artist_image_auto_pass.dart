import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sistrum/services/artist_images/artist_image_download.dart';
import 'package:sistrum/services/artist_images/artist_image_network.dart';
import 'package:sistrum/services/artist_images/artist_image_store.dart';
import 'package:sistrum/services/artist_images/deezer_artist_search.dart';

/// Names that never get a photo.
bool isSkippedArtistName(String name) {
  final key = artistImageKey(name);
  return key.isEmpty || key == 'various artists' || key == 'unknown artist';
}

/// Why a pass ended and what it changed.
class ArtistImageAutoResult {
  const ArtistImageAutoResult({
    required this.saved,
    required this.notFound,
    required this.stopped,
  });

  final int saved;
  final int notFound;
  final ArtistImageAutoStop? stopped;

  bool get changedSomething => saved > 0 || notFound > 0;
}

/// Why a pass stopped before it went through every name. Nothing is
/// recorded for the artist being looked at, so a later pass retries it.
enum ArtistImageAutoStop {
  /// The network is not one the setting allows.
  networkNotAllowed,

  /// Deezer or the image host failed.
  outage,

  /// The caller turned the feature off.
  disabled,
}

/// One background pass over [names]. Each artist without a record is searched
/// once on Deezer. Only an exact name match with a portrait is used; anything
/// else is recorded as not found, so the artist is not searched again.
Future<ArtistImageAutoResult> runArtistImageAutoPass({
  required List<String> names,
  required ArtistImageStore store,
  required http.Client client,
  required ArtistImageNetwork policy,
  required Future<ArtistNetworkKind> Function() readNetwork,
  required bool Function() stillEnabled,
  Duration pause = const Duration(seconds: 1),
}) async {
  final records = await store.readAll();
  final seen = <String>{};
  var saved = 0;
  var notFound = 0;

  ArtistImageAutoResult stop(ArtistImageAutoStop reason) =>
      ArtistImageAutoResult(saved: saved, notFound: notFound, stopped: reason);

  for (final name in names) {
    if (!stillEnabled()) return stop(ArtistImageAutoStop.disabled);
    if (isSkippedArtistName(name)) continue;
    final key = artistImageKey(name);
    if (!seen.add(key) || records.containsKey(key)) continue;

    if (!policy.allows(await readNetwork())) {
      return stop(ArtistImageAutoStop.networkNotAllowed);
    }

    final List<DeezerArtist> artists;
    try {
      artists = await DeezerArtistSearch(client).search(name);
    } on DeezerUnavailable {
      return stop(ArtistImageAutoStop.outage);
    }

    DeezerArtist? match;
    for (final artist in artists) {
      if (isExactArtistMatch(name, artist.name) && artist.pictureUrl != null) {
        match = artist;
        break;
      }
    }

    if (match == null) {
      await store.recordWithoutPhoto(key, ArtistImageStatus.notFound);
      notFound++;
    } else {
      final Uint8List bytes;
      try {
        bytes = await downloadArtistImage(client, match.pictureUrl!);
      } on ArtistImageDownloadFailed {
        return stop(ArtistImageAutoStop.outage);
      }
      await store.savePhoto(
        key: key,
        artist: match,
        bytes: bytes,
        status: ArtistImageStatus.auto,
      );
      saved++;
    }

    if (pause > Duration.zero) await Future<void>.delayed(pause);
  }
  return ArtistImageAutoResult(saved: saved, notFound: notFound, stopped: null);
}
