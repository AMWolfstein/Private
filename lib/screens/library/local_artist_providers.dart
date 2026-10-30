import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/models/local_library_item.dart';
import 'package:sistrum/providers/library_database_provider.dart';
import 'package:sistrum/providers/library_tag_credits_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/services/library/library_database.dart';
import 'package:sistrum/services/playback/listening_statistics.dart';

typedef ArtistTrackRequest = ({
  String artist,
  int offset,
  LibraryBrowseDbCursor? cursor,
});

/// Tracks per bounded page read from the library database.
const _artistPageSize = 40;

/// Bounded local reads shared by the artist page and its complete playback queue.
final localArtistTrackLoaderProvider =
    Provider<Future<LibraryBrowseDbPage> Function(ArtistTrackRequest)>((ref) {
      final credits = ref.watch(tagCreditScopeProvider);
      return (request) => ref
          .read(libraryDatabaseProvider)
          .getBrowseTrackPage(
            LibraryBrowseDbQuery(
              albumArtist: request.artist,
              artistCredit: LibraryArtistCredit.anyCredit,
              credits: credits,
              limit: _artistPageSize,
              offset: request.offset,
              cursor: request.cursor,
              sortMode: 'a-z',
              includeSingleTrackAlbums: true,
            ),
          );
    });

class LocalArtistTracks {
  const LocalArtistTracks(
    this.items, {
    required this.hasMore,
    this.loadingMore = false,
    this.error,
  });
  final List<LocalLibraryItem> items;
  final bool hasMore;
  final bool loadingMore;
  final Object? error;
}

/// The artist's picture: the artwork of the most recently added song that has
/// one. Null when none of the artist's songs has artwork.
final localArtistCoverProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, artist) async {
      ref.watch(localLibraryProvider.select((s) => s.loadedIndexVersion));
      final credits = ref.watch(tagCreditScopeProvider);
      final page = await ref
          .read(libraryDatabaseProvider)
          .getBrowseTrackPage(
            LibraryBrowseDbQuery(
              albumArtist: artist,
              artistCredit: LibraryArtistCredit.anyCredit,
              credits: credits,
              limit: _artistPageSize,
              sortMode: 'added',
              includeSingleTrackAlbums: true,
            ),
          );
      for (final row in page.rows) {
        final cover = _decodeArtistTrack(row).coverPath;
        if (cover != null && cover.isNotEmpty) return cover;
      }
      return null;
    });

final localArtistTracksProvider = AsyncNotifierProvider.autoDispose
    .family<LocalArtistTracksNotifier, LocalArtistTracks, String>(
      LocalArtistTracksNotifier.new,
    );

class LocalArtistTracksNotifier extends AsyncNotifier<LocalArtistTracks> {
  LocalArtistTracksNotifier(this.artist);
  final String artist;
  LibraryBrowseDbCursor? _cursor;
  int _generation = 0;

  @override
  Future<LocalArtistTracks> build() async {
    ref.watch(localLibraryProvider.select((s) => s.loadedIndexVersion));
    final generation = ++_generation;
    final page = await ref.watch(localArtistTrackLoaderProvider)((
      artist: artist,
      offset: 0,
      cursor: null,
    ));
    if (ref.mounted && generation == _generation) _cursor = page.nextCursor;
    return LocalArtistTracks(
      page.rows.map(_decodeArtistTrack).toList(),
      hasMore: page.rows.length == _artistPageSize,
    );
  }

  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(
      LocalArtistTracks(current.items, hasMore: true, loadingMore: true),
    );
    try {
      final page = await ref.read(localArtistTrackLoaderProvider)((
        artist: artist,
        offset: current.items.length,
        cursor: _cursor,
      ));
      if (!ref.mounted || generation != _generation) return;
      _cursor = page.nextCursor;
      final seen = current.items.map((item) => item.id).toSet();
      state = AsyncData(
        LocalArtistTracks([
          ...current.items,
          ...page.rows
              .map(_decodeArtistTrack)
              .where((item) => seen.add(item.id)),
        ], hasMore: page.rows.length == _artistPageSize),
      );
    } catch (error) {
      if (ref.mounted && generation == _generation) {
        state = AsyncData(
          LocalArtistTracks(current.items, hasMore: true, error: error),
        );
      }
    }
  }

  /// Playback includes every artist track, even when the UI has loaded one page.
  Future<List<LocalLibraryItem>> playbackQueue() async {
    final generation = _generation;
    final result = <LocalLibraryItem>[];
    await for (final items in _artistTrackPages(
      ref.read(localArtistTrackLoaderProvider),
      artist,
      () => ref.mounted && generation == _generation,
    )) {
      result.addAll(items);
    }
    return ref.mounted && generation == _generation ? result : const [];
  }
}

LocalLibraryItem _decodeArtistTrack(Map<String, dynamic> row) =>
    LocalLibraryItem.fromEnvelope(row);

/// Walks every page of [artist]'s tracks in order, yielding each page's rows
/// that are new to the walk. Stops at a short page, at an all-duplicate page,
/// or once [keepGoing] turns false.
Stream<List<LocalLibraryItem>> _artistTrackPages(
  Future<LibraryBrowseDbPage> Function(ArtistTrackRequest) load,
  String artist,
  bool Function() keepGoing,
) async* {
  final seen = <String>{};
  LibraryBrowseDbCursor? cursor;
  var offset = 0;
  while (keepGoing()) {
    final page = await load((artist: artist, offset: offset, cursor: cursor));
    if (!keepGoing()) return;
    final items = page.rows
        .map(_decodeArtistTrack)
        .where((item) => seen.add(item.id))
        .toList();
    if (items.isEmpty) return;
    yield items;
    if (page.rows.length < _artistPageSize) return;
    offset += page.rows.length;
    cursor = page.nextCursor;
  }
}

final localArtistPlayCountsLoaderProvider =
    Provider<Future<Map<String, int>> Function(List<String>)>(
      // Flushing happens once per Popular selection, before the paging loop
      // starts (PERF-601), not on every page's play-count read.
      (ref) => ListeningStatisticsStore.instance.playsForTracks,
    );

/// Flush hook so tests can observe the single pre-loop flush (PERF-601).
final listeningFlushProvider = Provider<Future<void> Function()>(
  (ref) => listeningRecorder.flush,
);

final localArtistPopularRandomProvider = Provider<Random>((ref) => Random());

/// Random tie-break draws for one artist page, keyed by track ID.
class _ArtistPopularTieBreaks {
  _ArtistPopularTieBreaks(this._random);

  final Random _random;
  final _draws = <String, double>{};

  /// The draw for [id], made once and then reused for the page's lifetime.
  double drawFor(String id) => _draws.putIfAbsent(id, _random.nextDouble);
}

// Keep independent random draws by ID across index refreshes, releasing them
// when the artist page's last listener leaves.
final _localArtistPopularTieBreaksProvider = Provider.autoDispose
    .family<_ArtistPopularTieBreaks, String>(
      (ref, artist) =>
          _ArtistPopularTieBreaks(ref.watch(localArtistPopularRandomProvider)),
    );

/// Recorded plays for a track. Play counts are stored under the file path and,
/// for tracks saved under a library id, under that id too; both are summed.
int _playsFor(Map<String, int> plays, LocalLibraryItem item) =>
    (plays[item.filePath] ?? 0) +
    (item.id == item.filePath ? 0 : plays[item.id] ?? 0);

/// Select at most 20 from the entire artist, rather than only the first page.
/// Random priorities give an unbiased, stable selection while this page is open
/// when there is no history; played tracks always outrank unplayed tracks.
final localArtistPopularProvider = FutureProvider.autoDispose
    .family<LocalArtistTracks, String>((ref, artist) async {
      final tieBreaks = ref.watch(_localArtistPopularTieBreaksProvider(artist));
      ref.watch(localLibraryProvider.select((s) => s.loadedIndexVersion));
      final load = ref.watch(localArtistTrackLoaderProvider);
      final counts = ref.watch(localArtistPlayCountsLoaderProvider);
      // Persisted plays must be visible to every page, not only the first;
      // flushing once before the loop is free when nothing is buffered.
      await ref.watch(listeningFlushProvider)();
      var selected = <({LocalLibraryItem item, int plays, double tie})>[];
      await for (final items in _artistTrackPages(
        load,
        artist,
        () => ref.mounted,
      )) {
        final keys = {
          for (final item in items) ...[item.filePath, item.id],
        }..remove('');
        final plays = await counts(keys.toList());
        if (!ref.mounted) return const LocalArtistTracks([], hasMore: false);
        selected.addAll(
          items.map(
            (item) => (
              item: item,
              plays: _playsFor(plays, item),
              tie: tieBreaks.drawFor(item.id),
            ),
          ),
        );
        selected.sort((a, b) {
          final rank = b.plays.compareTo(a.plays);
          return rank != 0 ? rank : b.tie.compareTo(a.tie);
        });
        selected = selected.take(20).toList();
      }
      return LocalArtistTracks(
        selected.map((row) => row.item).toList(),
        hasMore: false,
      );
    });
