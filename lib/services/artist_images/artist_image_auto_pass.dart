import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sistrum/services/artist_images/artist_image_download.dart';
import 'package:sistrum/services/artist_images/artist_image_network.dart';
import 'package:sistrum/services/animated_artwork/apple_artwork_client.dart';
import 'package:sistrum/services/animated_artwork/apple_artwork_parse.dart';
import 'package:sistrum/services/artist_images/artist_image_store.dart';
import 'package:sistrum/services/artist_images/artist_photo_sources.dart';
import 'package:sistrum/services/artist_images/deezer_artist_search.dart';
import 'package:sistrum/services/library/database/sqlite_helpers.dart'
    show normalizeSearchText;

/// Names that never get a photo.
bool isSkippedArtistName(String name) {
  final key = artistImageKey(name);
  return key.isEmpty || key == 'various artists' || key == 'unknown artist';
}

/// Orders names exactly like the Artists list: by the library's normalized
/// name key, compared as UTF-8 bytes (the SQLite BINARY order it uses).
/// Equal keys fall back to the raw name so the order is stable.
List<String> sortArtistNamesLikeArtistsList(Iterable<String> names) {
  final keyed =
      [
        for (final name in names)
          (key: utf8.encode(normalizeSearchText(name)), name: name),
      ]..sort((a, b) {
        final byKey = _compareBytes(a.key, b.key);
        return byKey != 0 ? byKey : a.name.compareTo(b.name);
      });
  return [for (final entry in keyed) entry.name];
}

int _compareBytes(List<int> a, List<int> b) {
  final length = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
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
  AppleArtworkClient? apple,
  required ArtistImageNetwork policy,
  required Future<ArtistNetworkKind> Function() readNetwork,
  required bool Function() stillEnabled,
  Duration pause = const Duration(seconds: 1),
  void Function()? onChanged,
  int batchSize = 5,
}) async {
  final generation = store.generation;
  final records = await store.readAll();
  var pendingChanges = 0;
  void flush() {
    if (pendingChanges > 0) {
      pendingChanges = 0;
      onChanged?.call();
    }
  }

  void changed() {
    pendingChanges++;
    if (pendingChanges >= batchSize) flush();
  }

  final seen = <String>{};
  var saved = 0;
  var notFound = 0;

  ArtistImageAutoResult stop(ArtistImageAutoStop reason) {
    flush();
    return ArtistImageAutoResult(
      saved: saved,
      notFound: notFound,
      stopped: reason,
    );
  }

  ArtistImageAutoStop? stopReason;
  Future<bool> allowed() async {
    if (!stillEnabled() || generation != store.generation) {
      stopReason = ArtistImageAutoStop.disabled;
      return false;
    }
    if (!policy.allows(await readNetwork())) {
      stopReason = ArtistImageAutoStop.networkNotAllowed;
      return false;
    }
    if (!stillEnabled() || generation != store.generation) {
      stopReason = ArtistImageAutoStop.disabled;
      return false;
    }
    return true;
  }

  try {
    for (final name in names) {
      if (!stillEnabled() || generation != store.generation) {
        return stop(ArtistImageAutoStop.disabled);
      }
      if (isSkippedArtistName(name)) continue;
      final key = artistImageKey(name);
      if (!seen.add(key) || records.containsKey(key)) continue;

      final ticket = store.ticketFor(key);
      if (!await allowed()) return stop(stopReason!);

      // Apple first when it is configured; Deezer when Apple fails or has no
      // usable portrait for the name. A Deezer failure stops the pass. An Apple
      // failure without a match leaves the name unrecorded for a later pass.
      ArtistPhotoCandidate? match;
      var appleFailed = false;
      var deezerFailed = false;
      if (apple != null) {
        try {
          match = _exactPhoto(name, await applePhotoCandidates(apple, name));
        } on AppleArtworkUnavailable {
          appleFailed = true;
        }
      }
      if (match == null) {
        try {
          match = _exactPhoto(name, await deezerPhotoCandidates(client, name));
        } on DeezerUnavailable {
          deezerFailed = true;
        }
      }

      if (!await allowed()) return stop(stopReason!);
      if (match == null && deezerFailed) {
        return stop(
          !stillEnabled()
              ? ArtistImageAutoStop.disabled
              : ArtistImageAutoStop.outage,
        );
      }

      if (match == null) {
        if (appleFailed) continue;
        final result = await store.recordWithoutPhoto(
          key,
          ArtistImageStatus.notFound,
          ticket: ticket,
          mayCommit: allowed,
        );
        if (result == ArtistImageSaveOutcome.saved) {
          notFound++;
          changed();
        }
        if (stopReason != null) return stop(stopReason!);
      } else {
        final Uint8List bytes;
        try {
          bytes = await downloadArtistImage(client, match.pictureUrl!);
        } on ArtistImageDownloadFailed {
          return stop(
            !stillEnabled()
                ? ArtistImageAutoStop.disabled
                : ArtistImageAutoStop.outage,
          );
        }
        final result = await store.savePhoto(
          key: key,
          deezerId: match.deezerId,
          bytes: bytes,
          status: ArtistImageStatus.auto,
          ticket: ticket,
          mayCommit: allowed,
        );
        if (result == ArtistImageSaveOutcome.saved) {
          saved++;
          changed();
        }
        if (stopReason != null) return stop(stopReason!);
      }

      if (pause > Duration.zero) await Future<void>.delayed(pause);
    }
    flush();
    return ArtistImageAutoResult(
      saved: saved,
      notFound: notFound,
      stopped: null,
    );
  } finally {
    flush();
  }
}

/// The first candidate with a portrait whose name matches [name] exactly.
ArtistPhotoCandidate? _exactPhoto(
  String name,
  List<ArtistPhotoCandidate> found,
) {
  for (final candidate in found) {
    if (candidate.pictureUrl != null &&
        isExactArtistMatch(name, candidate.name)) {
      return candidate;
    }
  }
  return null;
}
