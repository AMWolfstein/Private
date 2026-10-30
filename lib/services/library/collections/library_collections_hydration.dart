import 'dart:io';

import 'package:sistrum/core/models/library_collections.dart';
import 'package:sistrum/services/library/collections/library_collections_database.dart';
import 'package:sistrum/services/library/collections/library_collections_rows.dart';
import 'package:sistrum/services/library/collections/library_collections_worker.dart';

export 'package:sistrum/services/library/collections/library_collections_rows.dart'
    show HydratedPlaylistTracks;

const _workerRowThreshold = 64;

/// Small collections avoid isolate startup. Large snapshots leave JSON parsing,
/// model construction and all membership indices on the worker together.
Future<LibraryCollectionsState> hydrateLibraryCollectionsSnapshot(
  LibraryCollectionsSnapshot snapshot,
) async {
  if (snapshot.nativeRowsPath != null) {
    try {
      return await hydrateRowsInWorker<LibraryCollectionsState>(
        rows: const {},
        nativeRowsPath: snapshot.nativeRowsPath,
        nativeRowCount: snapshot.nativeRowCount,
      );
    } finally {
      await cleanupCollectionRows(
        nativeRowsPath: snapshot.nativeRowsPath,
        nativeRowsDirectory: snapshot.nativeRowsDirectory,
      );
    }
  }
  final rows =
      snapshot.lovedRows.length +
      snapshot.favoriteArtistRows.length +
      snapshot.playlistRows.length +
      snapshot.playlistTrackRows.length;
  if (rows < _workerRowThreshold &&
      !hasLargeJson([
        ...snapshot.lovedRows,
        ...snapshot.favoriteArtistRows,
        ...snapshot.playlistRows,
      ])) {
    return decodeLibraryCollectionsSnapshot(snapshot);
  }
  return hydrateRowsInWorker<LibraryCollectionsState>(
    rows: {
      CollectionRows.loved: snapshot.lovedRows,
      CollectionRows.artists: snapshot.favoriteArtistRows,
      CollectionRows.membership: snapshot.playlistTrackRows,
      CollectionRows.playlists: snapshot.playlistRows,
    },
  );
}

LibraryCollectionsState decodeLibraryCollectionsSnapshot(
  LibraryCollectionsSnapshot snapshot,
) {
  final accumulator = CollectionHydrationAccumulator()
    ..add(CollectionRows.loved, snapshot.lovedRows)
    ..add(CollectionRows.artists, snapshot.favoriteArtistRows)
    ..add(CollectionRows.membership, snapshot.playlistTrackRows)
    ..add(CollectionRows.playlists, snapshot.playlistRows);
  return accumulator.finish();
}

Future<HydratedPlaylistTracks> hydratePlaylistTracks(
  List<Map<String, dynamic>> rows, {
  required Set<String> knownKeys,
}) {
  final request = (rows: rows, knownKeys: knownKeys);
  if (rows.length < _workerRowThreshold && !hasLargeJson(rows)) {
    // Future.sync keeps a decode failure on the future, as the async body did.
    return Future.sync(() => decodePlaylistTracks(request));
  }
  return hydrateRowsInWorker<HydratedPlaylistTracks>(
    rows: {CollectionRows.playlistTracks: rows},
    knownKeys: knownKeys,
  );
}

Future<HydratedPlaylistTracks> hydratePlaylistTracksSnapshot(
  LibraryPlaylistTracksSnapshot snapshot, {
  required Set<String> knownKeys,
}) async {
  if (snapshot.nativeRowsPath == null) {
    return hydratePlaylistTracks(snapshot.rows, knownKeys: knownKeys);
  }
  try {
    return await hydrateRowsInWorker<HydratedPlaylistTracks>(
      rows: const {},
      knownKeys: knownKeys,
      nativeRowsPath: snapshot.nativeRowsPath,
      nativeRowCount: snapshot.nativeRowCount,
    );
  } finally {
    await cleanupCollectionRows(
      nativeRowsPath: snapshot.nativeRowsPath,
      nativeRowsDirectory: snapshot.nativeRowsDirectory,
    );
  }
}

Future<void> cleanupCollectionRows({
  String? nativeRowsPath,
  String? nativeRowsDirectory,
}) async {
  try {
    if (nativeRowsDirectory != null) {
      await Directory(nativeRowsDirectory).delete(recursive: true);
    } else if (nativeRowsPath != null) {
      await File(nativeRowsPath).delete();
    }
  } on FileSystemException {
    // The consuming worker may already have removed its row file.
  }
}

/// Backup writers can embed this trusted JSON fragment directly, avoiding a
/// second transfer of the large exported map from the UI to another worker.
Future<String> exportCollectionsBackupSnapshot(
  LibraryCollectionsSnapshot snapshot,
) async {
  try {
    return await runCollectionWorker<String>(
      mode: CollectionWorkerMode.backupJson,
      feed: (send) async {
        await send((
          path: snapshot.nativeRowsPath!,
          count: snapshot.nativeRowCount,
        ));
      },
    );
  } finally {
    await cleanupCollectionRows(
      nativeRowsDirectory: snapshot.nativeRowsDirectory,
      nativeRowsPath: snapshot.nativeRowsPath,
    );
  }
}
