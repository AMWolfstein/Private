import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/providers/library/library_database_provider.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/services/artist_images/artist_image_auto_pass.dart';
import 'package:sistrum/services/artist_images/artist_image_network.dart';
import 'package:sistrum/services/artist_images/artist_image_store.dart';
import 'package:sistrum/utils/logging/logger.dart';

final _log = AppLogger('ArtistImages');

/// How often the background lookup looks again while the setting is on.
const kArtistImageAutoInterval = Duration(minutes: 30);

Future<Directory> _artistImagesFolder() async {
  final support = await getApplicationSupportDirectory();
  return Directory(p.join(support.path, 'artist_images'));
}

final artistImageStoreProvider = Provider<ArtistImageStore>(
  (ref) =>
      ArtistImageStore(state: ArtistImageDb(), directory: _artistImagesFolder),
);

/// Counts photo changes, so open screens read the new state.
class ArtistImageRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

final artistImageRevisionProvider = NotifierProvider<ArtistImageRevision, int>(
  ArtistImageRevision.new,
);

/// The photo file for an artist name, or null when the artist shows its
/// album cover.
final artistImageFileProvider = FutureProvider.autoDispose
    .family<File?, String>((ref, artistName) async {
      ref.watch(artistImageRevisionProvider);
      final store = ref.watch(artistImageStoreProvider);
      final records = await store.readAll();
      final record = records[artistImageKey(artistName)];
      if (record == null) return null;
      return store.fileFor(record);
    });

/// Runs the background lookup while the setting is on: right away when it is
/// switched on, at each start while it is on, and every [kArtistImageAutoInterval].
/// Watching it from the app root keeps it alive for the whole session.
final artistImageAutoDownloadProvider = Provider<void>((ref) {
  final enabled = ref.watch(
    settingsProvider.select((s) => s.artistImagesAutoDownload),
  );
  final network = ref.watch(
    settingsProvider.select((s) => s.artistImagesNetwork),
  );
  if (!enabled) return;

  var active = true;
  var running = false;
  ref.onDispose(() => active = false);

  Future<void> pass() async {
    if (running || !active) return;
    running = true;
    final client = http.Client();
    try {
      final songs = await ref.read(libraryDatabaseProvider).listVisibleSongs();
      final names =
          songs
              .map(
                (Map<String, dynamic> row) =>
                    LocalLibraryItem.fromJson(row).artistName,
              )
              .toSet()
              .toList()
            ..sort();
      final result = await runArtistImageAutoPass(
        names: names,
        store: ref.read(artistImageStoreProvider),
        client: client,
        policy: ArtistImageNetwork.fromStored(network),
        readNetwork: readArtistNetworkKind,
        stillEnabled: () => active,
      );
      if (active && result.changedSomething) {
        ref.read(artistImageRevisionProvider.notifier).bump();
      }
    } catch (error) {
      _log.w('Background artist image lookup stopped: $error');
    } finally {
      client.close();
      running = false;
    }
  }

  unawaited(pass());
  final timer = Timer.periodic(
    kArtistImageAutoInterval,
    (_) => unawaited(pass()),
  );
  ref.onDispose(timer.cancel);
});

/// Bytes used by the artist photo folder, for the Cache settings page.
final artistImageBytesProvider = FutureProvider.autoDispose<int>((ref) {
  ref.watch(artistImageRevisionProvider);
  return ref.watch(artistImageStoreProvider).sizeBytes();
});

/// Removes every artist photo and record, so automatic lookups start over.
Future<void> clearArtistImages(WidgetRef ref) async {
  await ref.read(artistImageStoreProvider).clearAll();
  ref.read(artistImageRevisionProvider.notifier).bump();
}
