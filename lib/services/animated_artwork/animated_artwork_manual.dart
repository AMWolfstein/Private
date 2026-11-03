import 'package:http/http.dart' as http;
import 'package:sistrum/services/animated_artwork/animated_artwork_download.dart';
import 'package:sistrum/services/animated_artwork/animated_artwork_remux.dart';
import 'package:sistrum/services/animated_artwork/animated_artwork_store.dart';
import 'package:sistrum/services/animated_artwork/apple_artwork_client.dart';
import 'package:sistrum/services/animated_artwork/apple_artwork_parse.dart';

/// Catalog results of the requested kind for a search the user typed.
Future<List<AppleArtworkCandidate>> searchAppleArtwork(
  AppleArtworkClient api, {
  required AppleArtworkKind kind,
  required String term,
}) async {
  final results = await api.search(term);
  return results.where((c) => c.kind == kind).toList();
}

/// A pasted Apple Music album or artist link, resolved to its catalog entry.
/// Returns null when the text is not such a link or Apple has no entry for it.
Future<AppleArtworkCandidate?> resolveAppleArtworkLink(
  AppleArtworkClient api,
  String text,
) async {
  final link = parseAppleArtworkUrl(text);
  if (link == null) return null;
  return switch (link.kind) {
    AppleArtworkKind.album => api.albumDetails(link.id),
    AppleArtworkKind.artist => api.artistDetails(link.id),
  };
}

/// The motion video the catalog holds for a chosen entry, or null when there
/// is none. Throws when the catalog cannot answer.
Future<AppleMotionVideo?> chooseAppleVideo(
  AppleArtworkClient api,
  AppleArtworkCandidate candidate,
) => switch (candidate.kind) {
  AppleArtworkKind.album => api.albumVideo(candidate.id),
  AppleArtworkKind.artist => api.artistVideo(candidate.id),
};

/// Downloads a chosen catalog video and publishes it as the manual choice.
///
/// The published remote id lets automatic work and other records share the
/// same file. [isCancelled] is checked during the download, so closing the
/// sheet stops it; a cancelled save publishes nothing.
Future<AnimatedArtworkSaveOutcome> saveCatalogVideo({
  required AnimatedArtworkStore store,
  required http.Client client,
  required AnimatedArtworkKind kind,
  required String key,
  required AppleArtworkCandidate candidate,
  required AppleMotionVideo video,
  bool Function()? isCancelled,
}) async {
  final staged = await store.newStagingFile();
  final DownloadedAnimatedVideo downloaded;
  try {
    downloaded = await preparePlayableVideo(
      await downloadAppleMotionVideo(
        client: client,
        playlist: Uri.parse(video.url),
        output: staged,
        isCancelled: isCancelled,
      ),
    );
  } on Object {
    if (await staged.exists()) await staged.delete();
    rethrow;
  }
  return store.publishVideo(
    kind: kind,
    key: key,
    video: downloaded,
    status: AnimatedArtworkStatus.manual,
    remoteId: 'apple:${kind.name}:${candidate.id}:${video.key}',
  );
}

/// Copies a video the user picked from the device into owned storage and
/// publishes it as the manual choice. [source] is read as a byte stream, so
/// content URIs from the system picker never need a filesystem path.
Future<AnimatedArtworkSaveOutcome> saveImportedVideo({
  required AnimatedArtworkStore store,
  required AnimatedArtworkKind kind,
  required String key,
  required Stream<List<int>> source,
  int? declaredLength,
}) async {
  final staged = await store.newStagingFile();
  final DownloadedAnimatedVideo imported;
  try {
    imported = await preparePlayableVideo(
      await importAnimatedVideoStream(
        source: source,
        output: staged,
        declaredLength: declaredLength,
      ),
    );
  } on Object {
    if (await staged.exists()) await staged.delete();
    rethrow;
  }
  return store.publishVideo(
    kind: kind,
    key: key,
    video: imported,
    status: AnimatedArtworkStatus.manual,
  );
}

/// Removes the video and returns to the static artwork. The record stays as
/// a Reset, so automatic downloads do not put it back. Other artwork, such as
/// an artist photo, is not touched.
Future<AnimatedArtworkSaveOutcome> resetAnimatedVideo({
  required AnimatedArtworkStore store,
  required AnimatedArtworkKind kind,
  required String key,
}) => store.recordWithoutVideo(
  kind: kind,
  key: key,
  status: AnimatedArtworkStatus.reset,
);
