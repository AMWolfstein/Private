import 'dart:math';
import 'package:spotiflac_android/services/listening_statistics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/services/library_database.dart';

typedef ArtistTrackRequest = ({
  String artist,
  int offset,
  QueueLibraryDbCursor? cursor,
});

/// Bounded local reads shared by the artist page and its complete playback queue.
final localArtistTrackLoaderProvider =
    Provider<Future<QueueLibraryDbPage> Function(ArtistTrackRequest)>(
      (ref) =>
          (request) => LibraryDatabase.instance.getQueueTrackPageResult(
            QueueLibraryDbQuery(
              albumArtist: request.artist,
              limit: 40,
              offset: request.offset,
              cursor: request.cursor,
              sortMode: 'a-z',
              includeSingleTrackAlbums: true,
            ),
          ),
    );

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

final localArtistTracksProvider = AsyncNotifierProvider.autoDispose
    .family<LocalArtistTracksNotifier, LocalArtistTracks, String>(
      LocalArtistTracksNotifier.new,
    );

class LocalArtistTracksNotifier extends AsyncNotifier<LocalArtistTracks> {
  LocalArtistTracksNotifier(this.artist);
  final String artist;
  QueueLibraryDbCursor? _cursor;
  int _generation = 0;

  @override
  Future<LocalArtistTracks> build() async {
    ref.watch(localLibraryProvider.select((s) => s.loadedIndexVersion));
    final generation = ++_generation;
    if (!ref.watch(settingsProvider.select((s) => s.localLibraryEnabled))) {
      return const LocalArtistTracks([], hasMore: false);
    }
    final page = await ref.watch(localArtistTrackLoaderProvider)((
      artist: artist,
      offset: 0,
      cursor: null,
    ));
    if (ref.mounted && generation == _generation) _cursor = page.nextCursor;
    return LocalArtistTracks(
      page.rows.map(_decodeArtistTrack).toList(),
      hasMore: page.rows.length == 40,
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
        ], hasMore: page.rows.length == 40),
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
    if (!ref.read(settingsProvider).localLibraryEnabled) return const [];
    final generation = _generation;
    final load = ref.read(localArtistTrackLoaderProvider);
    final result = <LocalLibraryItem>[];
    final seen = <String>{};
    QueueLibraryDbCursor? cursor;
    var offset = 0;
    while (ref.mounted) {
      final page = await load((artist: artist, offset: offset, cursor: cursor));
      if (!ref.mounted || generation != _generation) return const [];
      final added = page.rows
          .map(_decodeArtistTrack)
          .where((item) => seen.add(item.id))
          .toList();
      result.addAll(added);
      if (page.rows.length < 40 || added.isEmpty) break;
      offset += page.rows.length;
      cursor = page.nextCursor;
    }
    return result;
  }
}

LocalLibraryItem _decodeArtistTrack(Map<String, dynamic> row) =>
    LocalLibraryItem.fromJson(Map<String, dynamic>.from(row["item"] as Map));

final localArtistPlayCountsLoaderProvider =
    Provider<Future<Map<String, int>> Function(List<String>)>(
      (ref) => (keys) async {
        await listeningRecorder.flush();
        return ListeningStatisticsStore.instance.playsForTracks(keys);
      },
    );

final localArtistPopularRandomProvider = Provider<Random>((ref) => Random());

// Keep independent random draws by ID across index refreshes, releasing them
// when the artist page's last listener leaves.
final _localArtistPopularPrioritiesProvider = Provider.autoDispose
    .family<Map<String, double>, String>((ref, artist) => {});

/// Select at most 20 from the entire artist, rather than only the first page.
/// Random priorities give an unbiased, stable selection while this page is open
/// when there is no history; played tracks always outrank unplayed tracks.
final localArtistPopularProvider = FutureProvider.autoDispose
    .family<LocalArtistTracks, String>((ref, artist) async {
      final priorities = ref.watch(
        _localArtistPopularPrioritiesProvider(artist),
      );
      ref.watch(localLibraryProvider.select((s) => s.loadedIndexVersion));
      if (!ref.watch(settingsProvider.select((s) => s.localLibraryEnabled))) {
        return const LocalArtistTracks([], hasMore: false);
      }
      final load = ref.watch(localArtistTrackLoaderProvider);
      final counts = ref.watch(localArtistPlayCountsLoaderProvider);
      final random = ref.watch(localArtistPopularRandomProvider);
      var selected = <({LocalLibraryItem item, int plays, double tie})>[];
      final seen = <String>{};
      QueueLibraryDbCursor? cursor;
      var offset = 0;
      while (ref.mounted) {
        final page = await load((
          artist: artist,
          offset: offset,
          cursor: cursor,
        ));
        if (!ref.mounted) return const LocalArtistTracks([], hasMore: false);
        final items = page.rows
            .map(_decodeArtistTrack)
            .where((item) => seen.add(item.id))
            .toList();
        if (items.isEmpty) break;
        final keys = {
          for (final item in items) ...[item.filePath, item.id],
        }..remove('');
        final plays = await counts(keys.toList());
        if (!ref.mounted) return const LocalArtistTracks([], hasMore: false);
        selected.addAll(
          items.map(
            (item) => (
              item: item,
              plays:
                  (plays[item.filePath] ?? 0) +
                  (item.id == item.filePath ? 0 : plays[item.id] ?? 0),
              tie: priorities.putIfAbsent(item.id, random.nextDouble),
            ),
          ),
        );
        selected.sort((a, b) {
          final rank = b.plays.compareTo(a.plays);
          return rank != 0 ? rank : b.tie.compareTo(a.tie);
        });
        selected = selected.take(20).toList();
        if (page.rows.length < 40) break;
        offset += page.rows.length;
        cursor = page.nextCursor;
      }
      return LocalArtistTracks(
        selected.map((row) => row.item).toList(),
        hasMore: false,
      );
    });
