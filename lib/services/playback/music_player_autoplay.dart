import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:sistrum/models/playable_media.dart';
import 'package:sistrum/services/library/library_database.dart';
import 'package:sistrum/services/playback/autoplay_personalization.dart';
import 'package:sistrum/services/playback/music_player_runtime.dart';
import 'package:sistrum/services/sqlite_helpers.dart' show normalizeLookupText;
import 'package:sistrum/utils/int_utils.dart';
import 'package:sistrum/utils/logger.dart';

final _log = AppLogger('MusicPlayer');

typedef AutoplayLibraryLoader =
    Future<List<PlayableMedia>> Function(PlayableMedia seed);

AutoplayLearningTrack autoplayLearningTrack(PlayableMedia media) =>
    AutoplayLearningTrack(
      source: media.source,
      title: media.title,
      artist: media.artist,
      album: media.album,
      genre: media.genre ?? '',
      duration: media.duration,
    );

/// Bounded database pages keep recommendation work independent of Library
/// size. Enabled scanned sources are local files.
Future<List<PlayableMedia>> loadAutoplayLibrary(
  PlayableMedia seed,
  MusicPlayerRuntime runtime,
) async {
  final database = runtime.dependencies.libraryDatabase;
  const query = QueueLibraryDbQuery();
  final count = (await database.getQueueCounts(query)).allTrackCount;
  final offset = count > 256 ? Random().nextInt(count - 255) : 0;
  final rows = [
    if (seed.artist.trim().isNotEmpty)
      ...(await database.getQueueTrackPage(
        QueueLibraryDbQuery(searchQuery: seed.artist, limit: 128),
      )).rows,
    ...(await database.getQueueTrackPage(
      QueueLibraryDbQuery(offset: offset, limit: 256),
    )).rows,
  ];
  final result = <PlayableMedia>[];
  for (final row in rows) {
    final data = (row['item'] as Map).cast<String, dynamic>();
    final source = data['filePath'] as String? ?? '';
    if (source.isEmpty) continue;
    // Do not interpret remote URLs as streamable Library items.
    if (source.startsWith('http://') || source.startsWith('https://')) continue;
    if (!source.startsWith('content://') && !await File(source).exists()) {
      continue;
    }
    final cover = data['coverPath'] as String? ?? data['coverUrl'] as String?;
    final seconds = readPositiveInt(data['duration']);
    result.add(
      PlayableMedia(
        id: data['id'] as String,
        source: source,
        title: data['trackName'] as String? ?? '',
        artist: data['artistName'] as String? ?? '',
        album: data['albumName'] as String? ?? '',
        genre: data['genre'] as String?,
        artUri: cover == null || cover.isEmpty
            ? null
            : cover.startsWith('/')
            ? Uri.file(cover).toString()
            : cover,
        duration: seconds == null ? null : Duration(seconds: seconds),
        bitDepth: readPositiveInt(data['bitDepth']),
        sampleRate: readPositiveInt(data['sampleRate']),
        bitrate: readPositiveInt(data['bitrate']),
        format: data['format'] as String?,
      ),
    );
  }
  return result;
}

/// Rank once per refill, so the visible queue is the actual playback order.
/// Related songs score higher, while recent plays and repeated artists lose
/// priority. Optional local learning adjusts this prior without audio analysis.
List<PlayableMedia> selectAutoplayTracks({
  required PlayableMedia seed,
  required List<PlayableMedia> candidates,
  required List<PlayableMedia> upcoming,
  required List<PlayableMedia> recent,
  required Set<String> dismissedSources,
  required Random random,
  int limit = 6,
  double Function(PlayableMedia)? preferenceAdjustment,
}) {
  String normalized(String? value) => normalizeLookupText(value);
  String songKey(PlayableMedia item) =>
      '${normalized(item.artist)}|${normalized(item.title)}';
  final sources = {
    seed.source,
    ...upcoming.map((item) => item.source),
    ...dismissedSources,
  };
  final songs = {songKey(seed), ...upcoming.map(songKey)};
  final seedArtist = normalized(seed.artist);
  final seedAlbum = normalized(seed.album);
  final seedGenre = normalized(seed.genre);
  final recentSources = <String, int>{};
  final recentSongs = <String, int>{};
  for (var i = 0; i < recent.length; i++) {
    recentSources[recent[i].source] = i;
    recentSongs[songKey(recent[i])] = i;
  }
  final scored = <(PlayableMedia, double, String)>[];
  for (final item in candidates) {
    final key = songKey(item);
    if (item.source.trim().isEmpty ||
        item.source.startsWith('http://') ||
        item.source.startsWith('https://') ||
        sources.contains(item.source) ||
        songs.contains(key)) {
      continue;
    }
    sources.add(item.source);
    songs.add(key);
    final artist = normalized(item.artist);
    var score = random.nextDouble() * 2;
    if (seedArtist.isNotEmpty && seedArtist == artist) {
      score += 5;
    }
    if (seedAlbum.isNotEmpty && seedAlbum == normalized(item.album)) {
      score += 3;
    }
    if (seedGenre.isNotEmpty && seedGenre == normalized(item.genre)) {
      score += 4;
    }
    if (preferenceAdjustment != null) score += preferenceAdjustment(item);
    // Match the latest source OR normalized song occurrence without walking
    // the entire listening history again for every candidate.
    final played = max(
      recentSources[item.source] ?? -1,
      recentSongs[key] ?? -1,
    );
    if (played >= 0) score -= 20 + played.toDouble();
    scored.add((item, score, artist));
  }
  final selected = <PlayableMedia>[];
  while (selected.length < limit && scored.isNotEmpty) {
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    final next = scored.removeAt(0);
    selected.add(next.$1);
    for (var i = 0; i < scored.length; i++) {
      final (item, score, artist) = scored[i];
      if (artist == next.$3) {
        scored[i] = (item, score - 4, artist);
      }
    }
  }
  return selected;
}

/// The queue, session and settings view that Autoplay reads and extends. The
/// handler supplies it through [_HandlerAutoplayQueue], so Autoplay itself never
/// reaches the handler's private state.
abstract interface class AutoplayQueueView {
  bool get autoplaySetting;
  bool get isDisposed;
  AudioServiceRepeatMode get repeatMode;
  int get index;
  int get mediaCount;
  PlayableMedia mediaAt(int i);
  MediaItem queueItemAt(int i);
  List<PlayableMedia> upcoming();
  List<PlayableMedia> recentlyPlayed();
  AutoplayPreferenceModel? get preferenceModel;
  Random get random;
  int get sessionQueueRevision;
  void appendAutoplayTracks(List<PlayableMedia> additions);
  void removeQueuedItem(MediaItem item);
}

class MusicAutoplay {
  MusicAutoplay(this.view, this.loadLibrary);

  final AutoplayQueueView view;
  final AutoplayLibraryLoader loadLibrary;
  final Set<String> _dismissed = {};
  Future<void>? _pending;
  int _generation = 0;
  (String, int)? _attempt;

  bool get enabled =>
      view.autoplaySetting && view.repeatMode == AudioServiceRepeatMode.none;

  int get manualInsertIndex {
    for (var i = view.index + 1; i < view.mediaCount; i++) {
      if (view.mediaAt(i).autoplay) return i;
    }
    return view.mediaCount;
  }

  void reset() {
    _generation++;
    _pending = null;
    _attempt = null;
    _dismissed.clear();
  }

  void dismiss(PlayableMedia item) => _dismissed.add(item.source);

  void updateMode() {
    reset();
    // Never remove the song already playing or a manually queued song.
    // Refresh suggestions when the enabled Library sources change too.
    for (var i = view.mediaCount - 1; i > view.index; i--) {
      if (view.mediaAt(i).autoplay) {
        view.removeQueuedItem(view.queueItemAt(i));
      }
    }
    _dismissed.clear();
    if (enabled) unawaited(fill());
  }

  Future<void> fill() async {
    if (!enabled ||
        view.isDisposed ||
        view.index < 0 ||
        view.index >= view.mediaCount) {
      return;
    }
    if (view.mediaCount - view.index - 1 >= 3) return;
    final pending = _pending;
    if (pending != null) return pending;
    final seed = view.mediaAt(view.index);
    final attempt = (seed.source, view.sessionQueueRevision);
    if (_attempt == attempt) return;
    _attempt = attempt;
    final operation = _fill(seed, _generation);
    _pending = operation;
    try {
      await operation;
    } finally {
      if (identical(_pending, operation)) _pending = null;
    }
  }

  Future<void> _fill(PlayableMedia seed, int generation) async {
    try {
      final candidates = await loadLibrary(seed);
      if (!enabled ||
          view.isDisposed ||
          generation != _generation ||
          view.index < 0) {
        return;
      }
      // Re-check the live queue after I/O: quick skips and manual additions
      // must not duplicate entries or replace the user's selected track.
      final current = view.mediaAt(view.index);
      final upcoming = view.upcoming();
      if (upcoming.length >= 3) return;
      final recent = view.recentlyPlayed();
      final model = view.preferenceModel;
      final revision = view.sessionQueueRevision;
      final random = view.random;
      List<PlayableMedia> ordinaryRanking() => selectAutoplayTracks(
        seed: current,
        candidates: candidates,
        upcoming: upcoming,
        recent: recent,
        dismissedSources: _dismissed,
        random: random,
        limit: 6 - upcoming.length,
      );
      List<PlayableMedia> selected;
      if (model == null) {
        selected = ordinaryRanking();
      } else {
        try {
          selected = await compute(_rankPersonalizedAutoplay, (
            current,
            candidates,
            upcoming,
            recent,
            Set<String>.of(_dismissed),
            model,
            random.nextInt(1 << 31),
            DateTime.now(),
            6 - upcoming.length,
          ), debugLabel: 'autoplay-ranking');
        } catch (error) {
          _log.w(
            'Personalized ranking unavailable; using ordinary autoplay: $error',
          );
          selected = ordinaryRanking();
        }
      }
      // The worker must not publish suggestions for an obsolete queue/seed.
      if (!enabled ||
          view.isDisposed ||
          generation != _generation ||
          revision != view.sessionQueueRevision ||
          view.index < 0 ||
          view.index >= view.mediaCount ||
          view.mediaAt(view.index).source != current.source) {
        return;
      }
      if (selected.isEmpty) return;
      view.appendAutoplayTracks([
        for (final item in selected)
          PlayableMedia.fromJson({...item.toJson(), 'autoplay': true})!,
      ]);
    } catch (error) {
      _log.w('Could not prepare Library Autoplay: $error');
    }
  }
}

typedef _AutoplayRankingInput = (
  PlayableMedia,
  List<PlayableMedia>,
  List<PlayableMedia>,
  List<PlayableMedia>,
  Set<String>,
  AutoplayPreferenceModel,
  int,
  DateTime,
  int,
);

/// Pass metadata and a frozen 64 KiB model only, never the player/runtime.
List<PlayableMedia> _rankPersonalizedAutoplay(_AutoplayRankingInput input) {
  final (
    seed,
    candidates,
    upcoming,
    recent,
    dismissed,
    model,
    randomSeed,
    at,
    limit,
  ) = input;
  final learningSeed = autoplayLearningTrack(seed);
  return selectAutoplayTracks(
    seed: seed,
    candidates: candidates,
    upcoming: upcoming,
    recent: recent,
    dismissedSources: dismissed,
    random: Random(randomSeed),
    limit: limit,
    preferenceAdjustment: (track) => model.rankAdjustment(
      autoplayLearningTrack(track),
      previous: learningSeed,
      at: at,
    ),
  );
}
