import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/models/local_library_item.dart';
import 'package:sistrum/models/track.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/providers/library_database_provider.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/services/native/media_file_bridge.dart';
import 'package:sistrum/services/playback/music_player/music_player_service.dart';
import 'package:sistrum/utils/files/file_access.dart';
import 'package:sistrum/utils/logging/logger.dart';

final _log = AppLogger('PlaybackProvider');

class PlaybackState {
  const PlaybackState();
}

class PlaybackController extends Notifier<PlaybackState> {
  PlaybackController({LibraryDatabase? library}) : _injectedLibrary = library;

  final LibraryDatabase? _injectedLibrary;

  LibraryDatabase get _library =>
      _injectedLibrary ?? ref.read(libraryDatabaseProvider);

  @override
  PlaybackState build() => const PlaybackState();

  Future<void> _ensureInternalPlayer() async {
    if (await ref.read(musicPlayerControllerProvider).ensureInitialized() ==
        null) {
      throw Exception('The built-in player could not be initialized.');
    }
  }

  /// Plays a local-library album/list starting at [startItem], queuing the rest
  /// so playback continues to the next track automatically.
  Future<void> playLocalLibraryQueue(
    List<LocalLibraryItem> items, {
    required LocalLibraryItem startItem,
  }) async {
    final playable = items
        .where(
          (i) => i.filePath.trim().isNotEmpty && !isCueVirtualPath(i.filePath),
        )
        .toList();
    if (playable.isEmpty) return;
    var startIndex = playable.indexWhere((i) => i.id == startItem.id);
    if (startIndex < 0) startIndex = 0;

    await _ensureInternalPlayer();
    await ref
        .read(musicPlayerControllerProvider)
        .playLocal(playable, initialIndex: startIndex);
  }

  /// Plays a prebuilt queue in the built-in player starting at [startIndex].
  Future<void> playMediaQueue(
    Iterable<PlayableMedia> queue, {
    required int startIndex,
  }) async {
    await _ensureInternalPlayer();
    final items = queue.toList(growable: false);
    if (items.isEmpty) return;
    final i = startIndex.clamp(0, items.length - 1);
    await ref
        .read(musicPlayerControllerProvider)
        .playAll(items, initialIndex: i);
  }

  Future<void> playTrackList(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;

    final safeStart = startIndex.clamp(0, tracks.length - 1);
    final resolved = await resolveLocalTracks(tracks);

    await _ensureInternalPlayer();
    final queue = <PlayableMedia>[];
    int? initialIndex;
    var skippedCueVirtualTrack = false;
    for (var index = 0; index < tracks.length; index++) {
      final item = resolved[index];
      if (item == null) continue;
      if (isCueVirtualPath(item.filePath)) {
        skippedCueVirtualTrack = true;
        continue;
      }
      // Keep the playlist's original order so Previous can reach earlier
      // tracks and reaching its end still respects the player's repeat mode.
      if (index >= safeStart) initialIndex ??= queue.length;
      // The resolved row, not a bare path, is the playback identity: it keeps
      // the library ID, audio facts and local-only artwork.
      queue.add(playableFromLocal(item));
    }

    if (queue.isNotEmpty) {
      _log.d('Playing ${queue.length} tracks in the internal player');
      await ref
          .read(musicPlayerControllerProvider)
          .playAll(queue, initialIndex: initialIndex ?? 0);
      return;
    }
    if (skippedCueVirtualTrack) {
      throw Exception(cueVirtualTrackRequiresSplitMessage);
    }
    throw Exception('No local audio file is available to play.');
  }

  /// Resolves playlist tracks to the local-library rows they refer to, keeping
  /// the requested order. Missing and unreadable files stay null.
  Future<List<LocalLibraryItem?>> resolveLocalTracks(List<Track> tracks) =>
      _resolveLocalTracks(tracks);

  /// Path-only projection of [resolveLocalTracks] for export callers.
  Future<List<String?>> resolveTrackFilePaths(List<Track> tracks) async => [
    for (final item in await resolveLocalTracks(tracks)) item?.filePath,
  ];

  Future<List<LocalLibraryItem?>> _resolveLocalTracks(
    List<Track> tracks,
  ) async {
    if (tracks.isEmpty) return const [];
    final localFuture = _library.findExistingBatch([
      for (final track in tracks)
        LocalLibraryBatchLookupRequest(
          id: (track.source ?? '').toLowerCase() == 'local' ? track.id : null,
          isrc: track.isrc,
          trackName: track.name,
          artistName: track.artistName,
        ),
    ]);
    final localMatches = await localFuture;

    final results = List<LocalLibraryItem?>.filled(tracks.length, null);
    final existsChecks = <String, Future<bool>>{};
    final unknownSafPaths = <String>{};
    final safPaths = <String>{
      for (final row in localMatches)
        if (isContentUri(
          stripCueTrackSuffix(row?['filePath']?.toString() ?? ''),
        ))
          stripCueTrackSuffix(row!['filePath'].toString()),
    }.toList(growable: false);
    for (var start = 0; start < safPaths.length; start += 64) {
      final batch = safPaths.sublist(
        start,
        (start + 64).clamp(0, safPaths.length),
      );
      try {
        final checks = await MediaFileBridge.safExistsBatch(batch);
        for (final path in batch) {
          final exists = checks[path];
          if (exists != null) {
            existsChecks[path] = Future.value(exists);
          } else {
            unknownSafPaths.add(path);
          }
        }
      } catch (_) {
        // Older bindings may lack the batch API; retain per-file fallback.
        unknownSafPaths.addAll(batch);
      }
    }
    var next = 0;
    final workerCount = tracks.length < 8 ? tracks.length : 8;

    Future<bool> pathExists(String path) {
      final realPath = stripCueTrackSuffix(path);
      return existsChecks.putIfAbsent(realPath, () => fileExists(path));
    }

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= tracks.length) return;
        final row = localMatches[index];
        final localPath = row?['filePath']?.toString() ?? '';
        if (localPath.isNotEmpty && await pathExists(localPath)) {
          results[index] = LocalLibraryItem.fromJson(row!);
        }
      }
    }

    await Future.wait(List.generate(workerCount, (_) => worker()));
    return results;
  }
}

final playbackProvider = NotifierProvider<PlaybackController, PlaybackState>(
  PlaybackController.new,
);
