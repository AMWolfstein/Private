import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:sistrum/services/playback/autoplay/autoplay_signal.dart';
import 'package:sistrum/services/playback/autoplay/autoplay_taste.dart';
import 'package:sistrum/services/playback/autoplay/autoplay_ranker.dart';
import 'package:sistrum/services/playback/autoplay/autoplay_sound_profile.dart';
import 'package:sistrum/services/playback/autoplay/autoplay_sound_signal.dart';
import 'package:sistrum/services/playback/autoplay/autoplay_sound_store.dart';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/core/models/playable_media.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/services/playback/autoplay/autoplay_personalization.dart';
import 'package:sistrum/services/playback/music_player/music_player_runtime.dart';
import 'package:sistrum/services/library/database/sqlite_helpers.dart'
    show normalizeLookupText;
import 'package:sistrum/utils/text/int_utils.dart';
import 'package:sistrum/utils/logging/logger.dart';

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
  const query = LibraryBrowseDbQuery();
  final count = (await database.getQueueCounts(query)).allTrackCount;
  const pages = 8, pageSize = 48;
  final random = Random();
  final whole = count <= pages * pageSize;
  final rows = [
    if (seed.artist.trim().isNotEmpty)
      ...(await database.getBrowseTrackPage(
        LibraryBrowseDbQuery(searchQuery: seed.artist, limit: 32),
      )).rows,
    for (var page = 0; page < (whole ? 1 : pages); page++)
      ...(await database.getBrowseTrackPage(
        LibraryBrowseDbQuery(
          offset: whole
              ? 0
              : min(
                  count - pageSize,
                  count * page ~/ pages + random.nextInt(count ~/ pages),
                ),
          limit: whole ? pages * pageSize : pageSize,
        ),
      )).rows,
  ];
  final result = <PlayableMedia>[];
  for (final row in rows) {
    final data = LocalLibraryItem.envelopeItem(row);
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
/// The genres of a tag such as `Pop; Dance/Electronic`, normalized.
Set<String> _autoplayGenres(String? value) => {
  for (final part in (value ?? '').split(RegExp(r'[,;/|&]')))
    if (normalizeLookupText(part) case final genre when genre.isNotEmpty) genre,
};

/// Songs that play between two by one artist, while other artists fit.
const _autoplayArtistGap = 4;

/// The latest songs, newest weighing most, that set the session's genres.
const _autoplaySessionWindow = 12;

/// A song autoplay picked, with the parts of its score: what the ranking
/// learns to weigh from the songs the listener keeps or skips. Each part is
/// in score points before its weight: `genre`, `artist` and `album` (the
/// seed's), `preference` (learned), `novelty` and `fatigue` (of the artist
/// in this session), and `signal:<name>` and `follow:<name>` per signal.
typedef AutoplayPick = ({PlayableMedia media, Map<String, double> parts});

/// Picks songs like [rankAutoplayTracks], without their score parts.
List<PlayableMedia> selectAutoplayTracks({
  required PlayableMedia seed,
  required List<PlayableMedia> candidates,
  required List<PlayableMedia> upcoming,
  required List<PlayableMedia> recent,
  required Set<String> dismissedSources,
  required Random random,
  int limit = 6,
  double Function(PlayableMedia)? preferenceAdjustment,
  double Function(PlayableMedia)? exploration,
  SoundAutoplaySignal? sound,
  List<AutoplaySignal> signals = const [],
  Map<String, double> weights = const {},
}) => [
  for (final pick in rankAutoplayTracks(
    seed: seed,
    candidates: candidates,
    upcoming: upcoming,
    recent: recent,
    dismissedSources: dismissedSources,
    random: random,
    limit: limit,
    preferenceAdjustment: preferenceAdjustment,
    exploration: exploration,
    signals: [...signals, ?sound],
    weights: weights,
  ))
    pick.media,
];

/// Rank once per refill, so the visible queue is the actual playback order.
/// Songs score by how well their genres fit the listening session (the
/// seed, the songs before it and the queued ones, newest weighing most),
/// with optional local learning on top. Artists heard or queued lately lose
/// priority, an artist does not return within [_autoplayArtistGap] songs or
/// twice in one refill while others fit, and songs of a picked album lose
/// priority, so a favorite artist cannot take over the queue. [signals] add
/// what metadata cannot tell, such as how well a song follows the one before.
/// [exploration] adds a sampled bonus for trying artists, and [weights]
/// multiply the score parts by name (1 when absent).
List<AutoplayPick> rankAutoplayTracks({
  required PlayableMedia seed,
  required List<PlayableMedia> candidates,
  required List<PlayableMedia> upcoming,
  required List<PlayableMedia> recent,
  required Set<String> dismissedSources,
  required Random random,
  int limit = 6,
  double Function(PlayableMedia)? preferenceAdjustment,
  double Function(PlayableMedia)? exploration,
  SoundAutoplaySignal? sound,
  List<AutoplaySignal> signals = const [],
  Map<String, double> weights = const {},
}) {
  signals = [...signals, ?sound];
  double weighted(Map<String, double> parts) {
    var total = 0.0;
    for (final MapEntry(:key, :value) in parts.entries) {
      total += (weights[key] ?? 1) * value;
    }
    return total;
  }

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
  final recentSources = <String, int>{};
  final recentSongs = <String, int>{};
  for (var i = 0; i < recent.length; i++) {
    recentSources[recent[i].source] = i;
    recentSongs[songKey(recent[i])] = i;
  }

  // The session in playback order: history, the seed (often its last entry
  // already), then the queued songs the picks follow.
  final session = <PlayableMedia>[];
  for (final item in [...recent, seed, ...upcoming]) {
    if (session.isEmpty || session.last.source != item.source) {
      session.add(item);
    }
  }
  final genreWeights = <String, double>{};
  var genreTotal = 0.0;
  // Songs back from the session's end, and plays, of each artist.
  final artistDistance = <String, int>{};
  final artistPlays = <String, int>{};
  for (var back = 0; back < session.length; back++) {
    final item = session[session.length - 1 - back];
    final artist = normalized(item.artist);
    if (artist.isNotEmpty) {
      artistDistance.putIfAbsent(artist, () => back);
      artistPlays[artist] = (artistPlays[artist] ?? 0) + 1;
    }
    if (back >= _autoplaySessionWindow) continue;
    final genres = _autoplayGenres(item.genre);
    if (genres.isEmpty) continue;
    final weight = pow(0.75, back).toDouble();
    genreTotal += weight;
    for (final genre in genres) {
      genreWeights[genre] = (genreWeights[genre] ?? 0) + weight / genres.length;
    }
  }

  final eligible = <PlayableMedia>[];
  for (final item in candidates) {
    if (item.source.trim().isEmpty ||
        item.source.startsWith('http://') ||
        item.source.startsWith('https://') ||
        !sources.add(item.source) ||
        !songs.add(songKey(item))) {
      continue;
    }
    eligible.add(item);
  }
  for (final signal in signals) {
    signal.prepare(session, eligible);
  }

  final scored =
      <
        ({
          PlayableMedia item,
          double score,
          String artist,
          String album,
          Map<String, double> parts,
        })
      >[];
  for (final item in eligible) {
    final key = songKey(item);
    final artist = normalized(item.artist);
    final album = normalized(item.album);
    final parts = <String, double>{};
    if (genreTotal > 0) {
      var fit = 0.0;
      for (final genre in _autoplayGenres(item.genre)) {
        fit += genreWeights[genre] ?? 0;
      }
      parts['genre'] = 6 * min(1.0, fit / genreTotal);
    }
    if (seedArtist.isNotEmpty && seedArtist == artist) parts['artist'] = 2;
    if (seedAlbum.isNotEmpty && seedAlbum == album) parts['album'] = 1;
    if (preferenceAdjustment != null) {
      parts['preference'] = preferenceAdjustment(item);
    }
    for (final signal in signals) {
      parts['signal:${signal.name}'] = signal.score(item);
    }
    var score = random.nextDouble() * 1.5;
    if (exploration != null) score += exploration(item);
    // Match the latest source OR normalized song occurrence without walking
    // the entire listening history again for every candidate.
    final played = max(
      recentSources[item.source] ?? -1,
      recentSongs[key] ?? -1,
    );
    if (played >= 0) {
      // Heard already: recency alone orders these.
      score -= 20 + played.toDouble();
    } else if (artist.isNotEmpty) {
      final distance = artistDistance[artist];
      if (distance == null) {
        // An artist the session has not reached yet.
        parts['novelty'] = 1;
      } else {
        parts['fatigue'] =
            -6 * pow(0.7, distance) - 1.5 * min(4, artistPlays[artist]!);
      }
    }
    scored.add((
      item: item,
      score: score + weighted(parts),
      artist: artist,
      album: album,
      parts: parts,
    ));
  }

  final selected = <AutoplayPick>[];
  // The artists that played last, newest at the end.
  final latest = [for (final item in session) normalized(item.artist)];
  final picked = <String>{};
  // The song the next pick follows.
  PlayableMedia? before = session.isEmpty ? null : session.last;
  while (selected.length < limit && scored.isNotEmpty) {
    final previous = latest.isEmpty ? '' : latest.last;
    final spaced = {
      ...latest.skip(max(0, latest.length - (_autoplayArtistGap - 1))),
      ...picked,
    };
    final follows = before;
    final totals = [for (final entry in scored) entry.score];
    // How each candidate follows the song before it, per signal.
    final transitions = [
      for (final signal in signals)
        follows == null
            ? null
            : [for (final entry in scored) signal.follow(follows, entry.item)],
    ];
    for (var s = 0; s < signals.length; s++) {
      final values = transitions[s];
      if (values == null) continue;
      final weight = weights['follow:${signals[s].name}'] ?? 1;
      for (var i = 0; i < scored.length; i++) {
        totals[i] += weight * values[i];
      }
    }
    int? best;
    // Artists spaced apart first, then only not twice in a row, then the
    // best of what is left.
    for (final rule in [
      spaced,
      {previous},
      const <String>{},
    ]) {
      for (var i = 0; i < scored.length; i++) {
        final entry = scored[i];
        if (entry.artist.isNotEmpty && rule.contains(entry.artist)) continue;
        if (best == null || totals[i] > totals[best]) best = i;
      }
      if (best != null) break;
    }
    final next = scored.removeAt(best!);
    selected.add((
      media: next.item,
      parts: {
        ...next.parts,
        for (var s = 0; s < signals.length; s++)
          if (transitions[s] case final values?)
            'follow:${signals[s].name}': values[best],
      },
    ));
    before = next.item;
    latest.add(next.artist);
    if (next.artist.isNotEmpty) picked.add(next.artist);
    if (next.album.isEmpty) continue;
    // Songs of one album, such as a compilation's, stay apart too.
    for (var i = 0; i < scored.length; i++) {
      final entry = scored[i];
      if (entry.album == next.album) {
        scored[i] = (
          item: entry.item,
          score: entry.score - 3,
          artist: entry.artist,
          album: entry.album,
          parts: entry.parts,
        );
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
  MusicAutoplay(
    this.view,
    this.loadLibrary, {
    bool Function()? soundMatching,
    AutoplayRanker? Function()? ranker,
    AutoplayTaste? Function()? taste,
  }) : _soundMatching = soundMatching ?? (() => false),
       _ranker = ranker ?? (() => null),
       _taste = taste ?? (() => null);

  final bool Function() _soundMatching;
  final AutoplayRanker? Function() _ranker;
  final AutoplayTaste? Function() _taste;
  final _soundStore = AutoplaySoundStore();

  Future<Map<String, AutoplaySoundProfile>> _loadSounds(
    Iterable<PlayableMedia> media,
    int generation,
  ) async {
    if (!_soundMatching() || view.isDisposed || generation != _generation) {
      return {};
    }
    final result = await _soundStore.loadAll(media.map((m) => m.source));
    return _soundMatching() && !view.isDisposed && generation == _generation
        ? result
        : {};
  }

  void dispose() => reset();

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
      final revision = view.sessionQueueRevision;
      final profiles = _soundMatching()
          ? await _loadSounds([
              current,
              ...recent.reversed.take(11),
              ...candidates,
            ], generation)
          : <String, AutoplaySoundProfile>{};
      if (generation != _generation || view.isDisposed || !enabled) return;
      final signals = <AutoplaySignal>[
        ?_soundSignal(profiles),
        ?await _taste()?.signal([...recent, current, ...upcoming], candidates),
      ];
      if (generation != _generation || view.isDisposed || !enabled) return;
      final model = view.preferenceModel;
      final ranker = _ranker();
      final weights = ranker?.weights ?? const <String, double>{};
      final random = view.random;
      List<AutoplayPick> ordinaryRanking() => rankAutoplayTracks(
        seed: current,
        candidates: candidates,
        upcoming: upcoming,
        recent: recent,
        dismissedSources: _dismissed,
        random: random,
        limit: 6 - upcoming.length,
        signals: signals,
        weights: weights,
      );
      List<AutoplayPick> selected;
      if (model == null && signals.isEmpty && weights.isEmpty) {
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
            weights,
            signals,
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
      for (final pick in selected) {
        ranker?.remember(pick.media.source, pick.parts);
      }
      view.appendAutoplayTracks([
        for (final pick in selected)
          PlayableMedia.fromJson({...pick.media.toJson(), 'autoplay': true})!,
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
  AutoplayPreferenceModel?,
  int,
  DateTime,
  int,
  Map<String, double>,
  List<AutoplaySignal>,
);

/// Pass metadata and a frozen 64 KiB model only, never the player/runtime.
List<AutoplayPick> _rankPersonalizedAutoplay(_AutoplayRankingInput input) {
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
    weights,
    signals,
  ) = input;
  final learningSeed = autoplayLearningTrack(seed);
  final exploration = model?.explore(Random(randomSeed ^ 0x51a7));
  return rankAutoplayTracks(
    seed: seed,
    candidates: candidates,
    upcoming: upcoming,
    recent: recent,
    dismissedSources: dismissed,
    random: Random(randomSeed),
    limit: limit,
    signals: signals,
    weights: weights,
    preferenceAdjustment: model == null
        ? null
        : (track) => model.rankAdjustment(
            autoplayLearningTrack(track),
            previous: learningSeed,
            at: at,
          ),
    exploration: exploration == null
        ? null
        : (track) => exploration.adjustment(autoplayLearningTrack(track)),
  );
}

SoundAutoplaySignal? _soundSignal(Map<String, AutoplaySoundProfile> profiles) =>
    profiles.isEmpty
    ? null
    : SoundAutoplaySignal({
        for (final e in profiles.entries) e.key: e.value.vector,
      });
