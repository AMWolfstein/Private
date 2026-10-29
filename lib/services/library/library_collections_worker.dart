import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:sistrum/services/library/library_collections_rows.dart';

enum CollectionWorkerMode { snapshot, playlist, backupJson }

typedef _CollectionWorkerRequest = ({
  SendPort result,
  CollectionWorkerMode mode,
});
typedef _CollectionRowBatch = ({
  CollectionRows kind,
  List<Map<String, dynamic>> rows,
});

typedef _NativeCollectionRows = ({String path, int? count});

/// A single giant compute argument copies every row map before the isolate
/// starts, still blocking the caller. Stream bounded batches instead. The
/// worker consumes JSON as it arrives; Isolate.exit transfers the final model
/// graph without another full copy on the UI isolate.
Future<T> hydrateRowsInWorker<T>({
  required Map<CollectionRows, List<Map<String, dynamic>>> rows,
  Set<String>? knownKeys,
  String? nativeRowsPath,
  int? nativeRowCount,
}) => runCollectionWorker<T>(
  mode: knownKeys == null
      ? CollectionWorkerMode.snapshot
      : CollectionWorkerMode.playlist,
  feed: (sendBatch) async {
    for (final entry in rows.entries) {
      for (var offset = 0; offset < entry.value.length; offset += 256) {
        final end = (offset + 256).clamp(0, entry.value.length);
        await sendBatch((
          kind: entry.key,
          rows: entry.value.sublist(offset, end),
        ));
      }
    }
    if (knownKeys != null) {
      var batch = <String>[];
      for (final key in knownKeys) {
        batch.add(key);
        if (batch.length < 256) continue;
        await sendBatch(batch);
        batch = <String>[];
      }
      if (batch.isNotEmpty) await sendBatch(batch);
    }
    if (nativeRowsPath != null) {
      await sendBatch((path: nativeRowsPath, count: nativeRowCount));
    }
  },
);

typedef SendCollectionBatch = Future<void> Function(Object batch);

Future<T> runCollectionWorker<T>({
  required CollectionWorkerMode mode,
  required Future<void> Function(SendCollectionBatch sendBatch) feed,
}) async {
  final replies = ReceivePort();
  final ready = Completer<SendPort>();
  final result = Completer<T>();
  Completer<void>? acknowledgement;
  // An error can arrive while batches are being sent, before the final await.
  result.future.ignore();
  final subscription = replies.listen((Object? message) {
    if (message is SendPort) {
      ready.complete(message);
    } else if (message == true) {
      acknowledgement?.complete();
    } else if (message is List<Object?> && message.length == 1) {
      result.complete(message.single as T);
    } else {
      final error = message is List<Object?> && message.length == 2
          ? RemoteError(message[0].toString(), message[1].toString())
          : StateError('Collections hydration worker exited without a result');
      if (!ready.isCompleted) ready.completeError(error);
      if (!result.isCompleted) result.completeError(error);
      if (acknowledgement case final pending? when !pending.isCompleted) {
        pending.completeError(error);
      }
    }
  });
  Isolate? isolate;
  try {
    isolate = await Isolate.spawn(
      _collectionHydrationWorker,
      (result: replies.sendPort, mode: mode),
      onError: replies.sendPort,
      onExit: replies.sendPort,
      debugName: 'library collections hydration',
    );
    final commands = await ready.future;
    Future<void> sendBatch(Object batch) async {
      final received = Completer<void>();
      acknowledgement = received;
      commands.send(batch);
      await received.future;
    }

    await feed(sendBatch);
    commands.send(null);
    return await result.future;
  } finally {
    isolate?.kill(priority: Isolate.immediate);
    await subscription.cancel();
    replies.close();
  }
}

void _collectionHydrationWorker(_CollectionWorkerRequest request) async {
  final commands = ReceivePort();
  final accumulator = CollectionHydrationAccumulator();
  final knownKeys = <String>{};
  request.result.send(commands.sendPort);
  await for (final Object? message in commands) {
    if (message case _CollectionRowBatch batch) {
      accumulator.add(batch.kind, batch.rows);
      request.result.send(true);
    } else if (message is List<String>) {
      knownKeys.addAll(message);
      request.result.send(true);
    } else if (message case _NativeCollectionRows input) {
      await _readNativeCollectionRows(input, accumulator);
      request.result.send(true);
    } else if (message == null) {
      commands.close();
      if (request.mode == CollectionWorkerMode.backupJson) {
        Isolate.exit(request.result, [
          jsonEncode(accumulator.finish(completePlaylists: true).toJson()),
        ]);
      }
      if (request.mode == CollectionWorkerMode.snapshot) {
        Isolate.exit(request.result, [accumulator.finish()]);
      }
      final tracks = accumulator.playlistTracks.toList(growable: false);
      final keys = tracks.map((entry) => entry.key).toSet();
      Isolate.exit(request.result, [
        HydratedPlaylistTracks(
          tracks: tracks,
          trackKeys: keys,
          membershipUnchanged:
              keys.length == knownKeys.length && keys.every(knownKeys.contains),
        ),
      ]);
    }
  }
}

Future<void> _readNativeCollectionRows(
  _NativeCollectionRows input,
  CollectionHydrationAccumulator accumulator,
) async {
  var count = 0;
  CollectionRows? previousKind;
  var batch = <Map<String, dynamic>>[];
  final lines = const LineSplitter().startChunkedConversion(
    _CollectionLineSink((line) {
      final decoded = jsonDecode(line) as Map<String, dynamic>;
      final kind = switch (decoded['kind']) {
        'backup_track' => CollectionRows.backupTracks,
        'playlist_track' => CollectionRows.playlistTracks,
        'loved' => CollectionRows.loved,
        'artist' => CollectionRows.artists,
        'membership' => CollectionRows.membership,
        'playlist' => CollectionRows.playlists,
        _ => throw const FormatException(
          'Unknown collection snapshot row kind',
        ),
      };
      if (previousKind != null &&
          (kind != previousKind || batch.length == 256)) {
        accumulator.add(previousKind!, batch);
        batch = <Map<String, dynamic>>[];
      }
      previousKind = kind;
      batch.add(Map<String, dynamic>.from(decoded['row'] as Map));
      count++;
    }),
  );
  try {
    // Decode file chunks asynchronously, then split and consume their lines
    // synchronously on this worker. A stream event per row adds avoidable
    // scheduling overhead to large snapshots.
    await for (final chunk in File(
      input.path,
    ).openRead().transform(utf8.decoder)) {
      lines.add(chunk);
    }
    lines.close();
    if (previousKind != null && batch.isNotEmpty) {
      accumulator.add(previousKind!, batch);
    }
    if (input.count != null && count != input.count) {
      throw const FormatException('Incomplete native collection snapshot');
    }
  } finally {
    await File(input.path).delete();
  }
}

class _CollectionLineSink implements Sink<String> {
  const _CollectionLineSink(this.onLine);
  final void Function(String) onLine;

  @override
  void add(String line) => onLine(line);

  @override
  void close() {}
}
