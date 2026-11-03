import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/providers/library/library_database_provider.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/providers/library/library_tag_credits_provider.dart';
import 'package:sistrum/providers/library/local_library_provider.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/services/animated_artwork/animated_artwork_auto_pass.dart';
import 'package:sistrum/services/animated_artwork/animated_artwork_store.dart';
import 'package:sistrum/services/animated_artwork/apple_artwork_client.dart';
import 'package:sistrum/services/artist_images/artist_image_auto_pass.dart'
    show isSkippedArtistName;
import 'package:sistrum/services/artist_images/artist_image_network.dart';
import 'package:sistrum/services/library/browse/library_tag_credits.dart';
import 'package:sistrum/utils/logging/logger.dart';

final _log = AppLogger('AnimatedArtwork');

/// How often the background lookup looks again while its setting is on.
const kAnimatedArtworkAutoInterval = Duration(minutes: 30);

/// One album or artist in the animated artwork store.
typedef AnimatedArtworkRef = ({AnimatedArtworkKind kind, String key});

AnimatedArtworkRef animatedAlbumRef(String albumTitle, String albumArtist) =>
    (
      kind: AnimatedArtworkKind.album,
      key: animatedAlbumKey(albumTitle, albumArtist),
    );

AnimatedArtworkRef animatedArtistRef(String artistName) => (
  kind: AnimatedArtworkKind.artist,
  key: animatedArtistKey(artistName),
);

/// The album a library row belongs to. The album artist is the tag when
/// present, otherwise the track artist, as on the album detail page.
AnimatedArtworkRef animatedAlbumRefForItem(LocalLibraryItem item) =>
    animatedAlbumRef(item.albumName, item.albumArtist ?? item.artistName);

Future<Directory> _animatedArtworkFolder() async {
  final support = await getApplicationSupportDirectory();
  return Directory(p.join(support.path, 'animated_artwork'));
}

final animatedArtworkStoreProvider = Provider<AnimatedArtworkStore>(
  (ref) => AnimatedArtworkStore(
    state: AnimatedArtworkDb(),
    directory: _animatedArtworkFolder,
  ),
);

/// One Apple client for the session, so its developer token is reused.
final appleArtworkClientProvider = Provider<AppleArtworkClient>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return AppleArtworkClient(client: client);
});

/// Counts video changes, so open screens read the new state.
class AnimatedArtworkRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

final animatedArtworkRevisionProvider =
    NotifierProvider<AnimatedArtworkRevision, int>(
      AnimatedArtworkRevision.new,
    );

/// The video file for one album or artist, or null when it shows the static
/// cover. Keyed by value, so each open screen gets its own answer.
final animatedArtworkFileProvider = FutureProvider.autoDispose
    .family<File?, AnimatedArtworkRef>((ref, target) async {
      ref.watch(animatedArtworkRevisionProvider);
      final store = ref.watch(animatedArtworkStoreProvider);
      final record = (await store.readAll())[animatedArtworkId(
        target.kind,
        target.key,
      )];
      if (record == null) return null;
      return store.fileFor(record);
    });

/// The video for the album a track belongs to. Looked up per track id, so a
/// reply for an earlier track cannot be shown for the current one.
final animatedVideoForTrackProvider = FutureProvider.autoDispose
    .family<File?, String>((ref, trackId) async {
      final item = await ref
          .read(localLibraryProvider.notifier)
          .getById(trackId);
      if (item == null) return null;
      return ref.watch(animatedArtworkFileProvider(animatedAlbumRefForItem(item)).future);
    });

/// Which entities a manual choice is working on right now. Automatic work
/// leaves them alone until the choice is saved or abandoned.
class AnimatedArtworkLocks {
  final _ids = <String>{};

  bool isLocked(AnimatedArtworkTarget target) =>
      _ids.contains(animatedArtworkId(target.kind, target.key));

  void lock(AnimatedArtworkKind kind, String key) =>
      _ids.add(animatedArtworkId(kind, key));

  void unlock(AnimatedArtworkKind kind, String key) =>
      _ids.remove(animatedArtworkId(kind, key));
}

final animatedArtworkLocksProvider = Provider<AnimatedArtworkLocks>(
  (ref) => AnimatedArtworkLocks(),
);

/// Progress of the background pass, or null before the first pass.
class AnimatedArtworkProgressNotifier
    extends Notifier<AnimatedArtworkProgress?> {
  @override
  AnimatedArtworkProgress? build() => null;

  void report(AnimatedArtworkProgress progress) => state = progress;

  void reset() => state = null;
}

final animatedArtworkProgressProvider =
    NotifierProvider<AnimatedArtworkProgressNotifier, AnimatedArtworkProgress?>(
      AnimatedArtworkProgressNotifier.new,
    );

/// Bytes used by the video folder, for the Cache settings page.
final animatedArtworkBytesProvider = FutureProvider.autoDispose<int>((ref) {
  ref.watch(animatedArtworkRevisionProvider);
  return ref.watch(animatedArtworkStoreProvider).sizeBytes();
});

/// Removes every video and record. Automatic downloads may fetch them again
/// later while their setting is on.
Future<void> clearAnimatedArtwork(WidgetRef ref) async {
  await ref.read(animatedArtworkStoreProvider).clearAll();
  ref.read(animatedArtworkProgressProvider.notifier).reset();
  ref.read(animatedArtworkRevisionProvider.notifier).bump();
}

/// The albums and artists in the visible library, as lookup targets. Albums
/// come first. Albums without a usable album artist are skipped.
Future<List<AnimatedArtworkTarget>> animatedArtworkTargets({
  required List<Map<String, dynamic>> songs,
  required TagCreditRules rules,
}) async {
  final albums = <String, AnimatedArtworkTarget>{};
  final artists = <String>{};
  for (final row in songs) {
    final item = LocalLibraryItem.fromJson(row);
    final albumArtist = (item.albumArtist ?? item.artistName).trim();
    if (item.albumName.trim().isNotEmpty &&
        albumArtist.isNotEmpty &&
        !isSkippedArtistName(albumArtist)) {
      final ref = animatedAlbumRefForItem(item);
      albums.putIfAbsent(
        ref.key,
        () => AnimatedArtworkTarget.album(
          title: item.albumName.trim(),
          albumArtist: albumArtist,
          trackCount: item.totalTracks,
        ),
      );
    }
    for (final name in splitTagCredits(
      item.artistName,
      TagCreditField.artist,
      rules,
    )) {
      if (!isSkippedArtistName(name)) artists.add(name);
    }
  }
  final sortedArtists = artists.toList()..sort();
  return [
    ...albums.values,
    for (final name in sortedArtists)
      AnimatedArtworkTarget.artist(artistName: name),
  ];
}

/// Runs the background lookup while its setting is on: at start, then every
/// [kAnimatedArtworkAutoInterval]. Turning it off stops new lookups only;
/// saved videos stay in place and keep playing.
final animatedArtworkAutoDownloadProvider = Provider<void>((ref) {
  final enabled = ref.watch(
    settingsProvider.select((s) => s.videoArtworkAutoDownload),
  );
  final network = ref.watch(
    settingsProvider.select((s) => s.videoArtworkNetwork),
  );
  final rules = ref.watch(tagCreditRulesProvider);
  if (!enabled) return;

  var active = true;
  var running = false;
  ref.onDispose(() => active = false);

  Future<void> pass() async {
    if (running || !active) return;
    running = true;
    try {
      final songs = await ref.read(libraryDatabaseProvider).listVisibleSongs();
      if (!active) return;
      final targets = await animatedArtworkTargets(songs: songs, rules: rules);
      if (!active) return;
      final store = ref.read(animatedArtworkStoreProvider);
      final result = await runAnimatedArtworkAutoPass(
        targets: targets,
        store: store,
        api: ref.read(appleArtworkClientProvider),
        downloadClient: ref.read(appleArtworkClientProvider).client,
        policy: ArtistImageNetwork.fromStored(network),
        readNetwork: readArtistNetworkKind,
        stillEnabled: () => active,
        isLocked: ref.read(animatedArtworkLocksProvider).isLocked,
        onProgress: (progress) {
          if (active) {
            ref.read(animatedArtworkProgressProvider.notifier).report(progress);
          }
        },
        onChanged: () {
          if (active) ref.read(animatedArtworkRevisionProvider.notifier).bump();
        },
      );
      _log.i(
        'Video artwork pass: ${result.progress.saved} saved, '
        '${result.progress.notFound} not found, '
        '${result.progress.failed} failed, stopped: ${result.stopped?.name}',
      );
    } catch (error) {
      _log.w('Background video artwork lookup stopped: $error');
    } finally {
      running = false;
    }
  }

  unawaited(pass());
  final timer = Timer.periodic(
    kAnimatedArtworkAutoInterval,
    (_) => unawaited(pass()),
  );
  ref.onDispose(timer.cancel);
});
