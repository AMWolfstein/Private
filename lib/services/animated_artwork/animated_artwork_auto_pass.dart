import 'package:http/http.dart' as http;
import 'package:sistrum/services/animated_artwork/animated_artwork_download.dart';
import 'package:sistrum/services/animated_artwork/animated_artwork_remux.dart';
import 'package:sistrum/services/animated_artwork/animated_artwork_store.dart';
import 'package:sistrum/services/animated_artwork/apple_artwork_client.dart';
import 'package:sistrum/services/animated_artwork/apple_artwork_parse.dart';
import 'package:sistrum/services/artist_images/artist_image_network.dart';

/// One album or artist the background lookup may try.
class AnimatedArtworkTarget {
  const AnimatedArtworkTarget.album({
    required this.title,
    required this.albumArtist,
    this.trackCount,
    this.upc,
  }) : kind = AnimatedArtworkKind.album,
       artistName = null;

  const AnimatedArtworkTarget.artist({required this.artistName})
    : kind = AnimatedArtworkKind.artist,
      title = null,
      albumArtist = null,
      trackCount = null,
      upc = null;

  final AnimatedArtworkKind kind;
  final String? title;
  final String? albumArtist;
  final String? artistName;

  /// The local track count, when the file tags state it. Used only to tell
  /// editions apart, never copied into the library.
  final int? trackCount;
  final String? upc;

  String get key => kind == AnimatedArtworkKind.album
      ? animatedAlbumKey(title!, albumArtist!)
      : animatedArtistKey(artistName!);
}

/// Why a pass ended before it finished every target.
enum AnimatedArtworkAutoStop {
  networkNotAllowed,
  outage,
  disabled,
}

class AnimatedArtworkProgress {
  const AnimatedArtworkProgress({
    this.total = 0,
    this.completed = 0,
    this.saved = 0,
    this.notFound = 0,
    this.failed = 0,
    this.skipped = 0,
  });

  final int total;

  /// Targets that reached an outcome in this pass, including skipped ones.
  final int completed;
  final int saved;
  final int notFound;

  /// Targets whose request failed. They are not recorded and retry later.
  final int failed;

  /// Targets that already had a record, so no request was sent.
  final int skipped;

  AnimatedArtworkProgress copyWith({
    int? total,
    int? completed,
    int? saved,
    int? notFound,
    int? failed,
    int? skipped,
  }) => AnimatedArtworkProgress(
    total: total ?? this.total,
    completed: completed ?? this.completed,
    saved: saved ?? this.saved,
    notFound: notFound ?? this.notFound,
    failed: failed ?? this.failed,
    skipped: skipped ?? this.skipped,
  );
}

class AnimatedArtworkAutoResult {
  const AnimatedArtworkAutoResult({
    required this.progress,
    required this.stopped,
  });

  final AnimatedArtworkProgress progress;
  final AnimatedArtworkAutoStop? stopped;
}

/// Consecutive network failures that end a pass as an outage.
const kAnimatedArtworkMaxNetworkFailures = 3;

/// One background pass over [targets]. Only entities without a video, a Reset
/// or a recent miss are looked up. A match must be exact on title and album
/// artist (or artist name), and only one exact catalog match is accepted.
Future<AnimatedArtworkAutoResult> runAnimatedArtworkAutoPass({
  required List<AnimatedArtworkTarget> targets,
  required AnimatedArtworkStore store,
  required AppleArtworkClient api,
  required http.Client downloadClient,
  required ArtistImageNetwork policy,
  required Future<ArtistNetworkKind> Function() readNetwork,
  required bool Function() stillEnabled,
  DateTime Function()? clock,
  Duration pause = const Duration(seconds: 2),
  Duration retryAfter = kAnimatedArtworkRetryAfter,
  int batchSize = 5,
  void Function(AnimatedArtworkProgress progress)? onProgress,
  void Function()? onChanged,

  /// True while the user is choosing this entity by hand. Automatic work
  /// leaves such an entity alone.
  bool Function(AnimatedArtworkTarget target)? isLocked,
}) async {
  final now = clock ?? DateTime.now;
  final generation = store.generation;
  final records = await store.readAll();
  var progress = AnimatedArtworkProgress(total: targets.length);
  var pendingChanges = 0;
  var networkFailures = 0;
  AnimatedArtworkAutoStop? stopReason;

  void report() => onProgress?.call(progress);
  void flush() {
    if (pendingChanges > 0) {
      pendingChanges = 0;
      onChanged?.call();
    }
  }

  bool stillCurrent() => stillEnabled() && generation == store.generation;

  Future<bool> allowed() async {
    if (!stillCurrent()) {
      stopReason = AnimatedArtworkAutoStop.disabled;
      return false;
    }
    if (!policy.allows(await readNetwork())) {
      stopReason = AnimatedArtworkAutoStop.networkNotAllowed;
      return false;
    }
    if (!stillCurrent()) {
      stopReason = AnimatedArtworkAutoStop.disabled;
      return false;
    }
    return true;
  }

  void counted({bool change = false}) {
    progress = progress.copyWith(completed: progress.completed + 1);
    if (change) {
      pendingChanges++;
      if (pendingChanges >= batchSize) flush();
    }
    report();
  }

  Future<_Outcome> recordMiss(
    AnimatedArtworkTarget target,
    AnimatedArtworkTicket ticket,
  ) async {
    final result = await store.recordWithoutVideo(
      kind: target.kind,
      key: target.key,
      status: AnimatedArtworkStatus.notFound,
      ticket: ticket,
      mayCommit: allowed,
    );
    return result == AnimatedArtworkSaveOutcome.saved
        ? _Outcome.notFound
        : _Outcome.superseded;
  }

  /// One target: look it up, then record its outcome. Only a publish or a
  /// miss changes the library-facing state; failures are never recorded.
  Future<_Outcome> attempt(
    AnimatedArtworkTarget target,
    AnimatedArtworkTicket ticket,
  ) async {
    if (isLocked?.call(target) ?? false) return _Outcome.superseded;
    final _Found found;
    try {
      found = await _lookup(target, api);
    } on AppleArtworkUnavailable {
      return _Outcome.failed;
    }
    if (!await allowed()) return _Outcome.disabled;
    if (found.video == null) {
      return recordMiss(target, ticket);
    }

    final staged = await store.newStagingFile();
    final DownloadedAnimatedVideo video;
    try {
      video = await preparePlayableVideo(
        await downloadAppleMotionVideo(
          client: downloadClient,
          playlist: Uri.parse(found.video!.url),
          output: staged,
          isCancelled: () => !stillCurrent(),
        ),
      );
    } on AnimatedVideoDownloadException catch (error) {
      switch (error.failure) {
        case AnimatedVideoFailure.cancelled:
          return _Outcome.disabled;
        case AnimatedVideoFailure.network:
        case AnimatedVideoFailure.incomplete:
          // Expired URLs and dropped connections land here: not recorded.
          return _Outcome.failed;
        case AnimatedVideoFailure.unsupportedMedia:
        case AnimatedVideoFailure.tooLarge:
        case AnimatedVideoFailure.invalidContainer:
          // A stable answer about this video, so it is recorded as a miss.
          return recordMiss(target, ticket);
      }
    }
    final result = await store.publishVideo(
      kind: target.kind,
      key: target.key,
      video: video,
      status: AnimatedArtworkStatus.auto,
      remoteId: found.remoteId,
      ticket: ticket,
      mayCommit: allowed,
    );
    return result == AnimatedArtworkSaveOutcome.saved
        ? _Outcome.saved
        : _Outcome.superseded;
  }

  final seen = <String>{};
  try {
    for (final target in targets) {
      if (!stillCurrent()) {
        stopReason = AnimatedArtworkAutoStop.disabled;
        break;
      }
      final id = animatedArtworkId(target.kind, target.key);
      if (!seen.add(id) || _alreadyDecided(records[id], now(), retryAfter)) {
        progress = progress.copyWith(skipped: progress.skipped + 1);
        counted();
        continue;
      }

      final ticket = store.ticketFor(target.kind, target.key);
      if (!await allowed()) break;

      final outcome = await attempt(target, ticket);
      switch (outcome) {
        case _Outcome.saved:
          progress = progress.copyWith(saved: progress.saved + 1);
          networkFailures = 0;
          counted(change: true);
        case _Outcome.notFound:
          progress = progress.copyWith(notFound: progress.notFound + 1);
          networkFailures = 0;
          counted(change: true);
        case _Outcome.superseded:
          networkFailures = 0;
          counted();
        case _Outcome.failed:
          networkFailures++;
          progress = progress.copyWith(failed: progress.failed + 1);
          counted();
        case _Outcome.disabled:
          stopReason = AnimatedArtworkAutoStop.disabled;
      }
      if (stopReason != null) break;
      if (networkFailures >= kAnimatedArtworkMaxNetworkFailures) {
        stopReason = AnimatedArtworkAutoStop.outage;
        break;
      }
      if (pause > Duration.zero) await Future<void>.delayed(pause);
    }
  } finally {
    flush();
    report();
  }
  return AnimatedArtworkAutoResult(progress: progress, stopped: stopReason);
}

enum _Outcome { saved, notFound, superseded, failed, disabled }

bool _alreadyDecided(
  AnimatedArtworkRecord? existing,
  DateTime now,
  Duration retryAfter,
) {
  if (existing == null) return false;
  if (existing.status != AnimatedArtworkStatus.notFound) return true;
  return now.millisecondsSinceEpoch - existing.checkedAtMs <
      retryAfter.inMilliseconds;
}


class _Found {
  const _Found(this.video, this.remoteId);
  final AppleMotionVideo? video;
  final String? remoteId;
}

/// Resolves one target to the single exact catalog match and its video.
/// Ambiguous or missing matches resolve to no video.
Future<_Found> _lookup(AnimatedArtworkTarget target, AppleArtworkClient api) async {
  if (target.kind == AnimatedArtworkKind.album) {
    final candidates = await api.search('${target.title} ${target.albumArtist}');
    final match = matchAppleAlbum(
      albumTitle: target.title!,
      albumArtist: target.albumArtist!,
      localTrackCount: target.trackCount,
      localUpc: target.upc,
      candidates: candidates,
    );
    if (match.outcome != AppleMatchOutcome.matched) return const _Found(null, null);
    final id = match.candidate!.id;
    final video = await api.albumVideo(id);
    return _Found(video, video == null ? null : 'apple:album:$id:${video.key}');
  }
  final candidates = await api.search(target.artistName!);
  final match = matchAppleArtist(
    artistName: target.artistName!,
    candidates: candidates,
  );
  if (match.outcome != AppleMatchOutcome.matched) return const _Found(null, null);
  final id = match.candidate!.id;
  final video = await api.artistVideo(id);
  return _Found(video, video == null ? null : 'apple:artist:$id:${video.key}');
}
