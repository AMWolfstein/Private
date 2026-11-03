import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/animated_artwork/animated_artwork_download.dart';
import 'package:sistrum/services/animated_artwork/animated_artwork_store.dart';

/// A state whose writes can be made to fail, to test that a database
/// failure leaves the previous video in place.
class _FlakyState extends MemoryAnimatedArtworkState {
  bool failPut = false;

  @override
  Future<void> put(AnimatedArtworkRecord record) async {
    if (failPut) throw const FileSystemException('disk full');
    return super.put(record);
  }
}

Uint8List _bytes(int seed) => Uint8List.fromList(
  List.generate(64, (i) => (i * seed + 1) & 0xff)
    ..setRange(4, 8, 'ftyp'.codeUnits)
    ..setRange(40, 44, 'moov'.codeUnits),
);

void main() {
  late Directory dir;
  late _FlakyState state;
  late AnimatedArtworkStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('aa_store_');
    state = _FlakyState();
    store = AnimatedArtworkStore(
      state: state,
      directory: () async => Directory('${dir.path}/animated_artwork'),
    );
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// A downloaded-looking staged file, as the download step would leave it.
  Future<DownloadedAnimatedVideo> staged(int seed) async {
    final file = await store.newStagingFile();
    await file.writeAsBytes(_bytes(seed));
    return DownloadedAnimatedVideo(file: file, bytes: 64, width: 1200, height: 1600);
  }

  const album = AnimatedArtworkKind.album;
  final key = animatedAlbumKey('Abbey Road', 'The Beatles');

  Future<AnimatedArtworkSaveOutcome> publish(
    DownloadedAnimatedVideo video, {
    required AnimatedArtworkStatus status,
    String? remoteId,
    AnimatedArtworkKind kind = album,
    String? forKey,
    AnimatedArtworkTicket? ticket,
    Future<bool> Function()? mayCommit,
  }) => store.publishVideo(
    kind: kind,
    key: forKey ?? key,
    video: video,
    status: status,
    remoteId: remoteId,
    ticket: ticket,
    mayCommit: mayCommit,
  );

  Future<String> fileNameOf(AnimatedArtworkKind kind, String k) async {
    final record = await store.recordFor(kind, k);
    return record!.fileName!;
  }

  group('keys', () {
    test('album identity keeps the edition in the title', () {
      expect(
        animatedAlbumKey('Abbey Road', 'The Beatles') ==
            animatedAlbumKey('Abbey Road (Deluxe)', 'The Beatles'),
        isFalse,
      );
    });

    test('album and artist keys never collide', () {
      expect(
        animatedArtworkId(AnimatedArtworkKind.album, animatedAlbumKey('Nina', 'Nina')),
        isNot(animatedArtworkId(AnimatedArtworkKind.artist, animatedArtistKey('Nina'))),
      );
    });

    test('Arabic names are kept, punctuation is not', () {
      expect(animatedArtistKey('أم كلثوم'), 'أم كلثوم');
      expect(animatedArtistKey('AC/DC'), animatedArtistKey('ac dc'));
    });
  });

  group('publishing', () {
    test('an automatic result fills an empty entity', () async {
      final outcome = await publish(
        await staged(3),
        status: AnimatedArtworkStatus.auto,
      );
      expect(outcome, AnimatedArtworkSaveOutcome.saved);
      final record = await store.recordFor(album, key);
      expect(record?.hasVideo, isTrue);
      expect(await store.fileFor(record!), isNotNull);
    });

    test('the staged file is consumed, not left behind', () async {
      final video = await staged(3);
      await publish(video, status: AnimatedArtworkStatus.auto);
      expect(video.file.existsSync(), isFalse);
    });

    test('a manual choice replaces an automatic video and removes it', () async {
      await publish(await staged(3), status: AnimatedArtworkStatus.auto);
      final old = await fileNameOf(album, key);

      final outcome = await publish(
        await staged(5),
        status: AnimatedArtworkStatus.manual,
      );
      expect(outcome, AnimatedArtworkSaveOutcome.saved);
      expect(await fileNameOf(album, key), isNot(old));
      expect(File('${dir.path}/animated_artwork/$old').existsSync(), isFalse);
    });

    test('an automatic result never replaces a manual video', () async {
      await publish(await staged(5), status: AnimatedArtworkStatus.manual);
      final video = await staged(3);
      final outcome = await publish(video, status: AnimatedArtworkStatus.auto);
      expect(outcome, AnimatedArtworkSaveOutcome.kept);
      expect(video.file.existsSync(), isFalse);
      expect((await store.recordFor(album, key))?.status,
          AnimatedArtworkStatus.manual);
    });

    test('an automatic result may retry an entity with only a recent miss', () async {
      await store.recordWithoutVideo(
        kind: album,
        key: key,
        status: AnimatedArtworkStatus.notFound,
      );
      final outcome = await publish(
        await staged(3),
        status: AnimatedArtworkStatus.auto,
      );
      expect(outcome, AnimatedArtworkSaveOutcome.saved);
      expect((await store.recordFor(album, key))?.hasVideo, isTrue);
    });

    test('a miss never replaces a video', () async {
      await publish(await staged(3), status: AnimatedArtworkStatus.manual);
      final outcome = await store.recordWithoutVideo(
        kind: album,
        key: key,
        status: AnimatedArtworkStatus.notFound,
      );
      expect(outcome, AnimatedArtworkSaveOutcome.kept);
      expect((await store.recordFor(album, key))?.hasVideo, isTrue);
    });

    test('a failed database write keeps the previous video intact', () async {
      await publish(await staged(3), status: AnimatedArtworkStatus.auto);
      final old = await fileNameOf(album, key);

      state.failPut = true;
      await expectLater(
        publish(await staged(5), status: AnimatedArtworkStatus.manual),
        throwsA(isA<FileSystemException>()),
      );
      state.failPut = false;

      final record = await store.recordFor(album, key);
      expect(record?.fileName, old);
      expect(File('${dir.path}/animated_artwork/$old').existsSync(), isTrue);
      final leftovers = Directory('${dir.path}/animated_artwork')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.startsWith('album_'))
          .toList();
      expect(leftovers, [old]);
    });

    test('a video shared by two records is removed only with its last record', () async {
      const otherKey = 'other';
      await publish(
        await staged(3),
        status: AnimatedArtworkStatus.auto,
        remoteId: 'apple:album:1:motionDetailTall',
      );
      final shared = await fileNameOf(album, key);

      final second = await publish(
        await staged(9),
        status: AnimatedArtworkStatus.auto,
        remoteId: 'apple:album:1:motionDetailTall',
        forKey: otherKey,
      );
      expect(second, AnimatedArtworkSaveOutcome.saved);
      expect(await fileNameOf(album, otherKey), shared);

      await store.recordWithoutVideo(
        kind: album,
        key: key,
        status: AnimatedArtworkStatus.reset,
      );
      expect(
        File('${dir.path}/animated_artwork/$shared').existsSync(),
        isTrue,
        reason: 'another record still references the file',
      );

      await store.recordWithoutVideo(
        kind: album,
        key: otherKey,
        status: AnimatedArtworkStatus.reset,
      );
      expect(File('${dir.path}/animated_artwork/$shared').existsSync(), isFalse);
    });

    test('album and artist associations are independent', () async {
      await publish(await staged(3), status: AnimatedArtworkStatus.auto);
      await publish(
        await staged(7),
        status: AnimatedArtworkStatus.manual,
        kind: AnimatedArtworkKind.artist,
        forKey: animatedArtistKey('The Beatles'),
      );
      final all = await store.readAll();
      expect(all.length, 2);
      expect(all[animatedArtworkId(album, key)]?.status,
          AnimatedArtworkStatus.auto);
      expect(
        all[animatedArtworkId(AnimatedArtworkKind.artist, animatedArtistKey('The Beatles'))]
            ?.status,
        AnimatedArtworkStatus.manual,
      );
    });
  });

  group('reset and clear', () {
    test('Reset removes the video and blocks automatic replacement', () async {
      await publish(await staged(3), status: AnimatedArtworkStatus.auto);
      final name = await fileNameOf(album, key);

      await store.recordWithoutVideo(
        kind: album,
        key: key,
        status: AnimatedArtworkStatus.reset,
      );
      expect(File('${dir.path}/animated_artwork/$name').existsSync(), isFalse);
      expect((await store.recordFor(album, key))?.hasVideo, isFalse);

      final video = await staged(3);
      expect(
        await publish(video, status: AnimatedArtworkStatus.auto),
        AnimatedArtworkSaveOutcome.kept,
      );
    });

    test('a new manual choice replaces the Reset state', () async {
      await store.recordWithoutVideo(
        kind: album,
        key: key,
        status: AnimatedArtworkStatus.reset,
      );
      expect(
        await publish(await staged(5), status: AnimatedArtworkStatus.manual),
        AnimatedArtworkSaveOutcome.saved,
      );
      expect((await store.recordFor(album, key))?.hasVideo, isTrue);
    });

    test('a manual choice supersedes an automatic download in flight', () async {
      final ticket = store.ticketFor(album, key);
      await publish(await staged(5), status: AnimatedArtworkStatus.manual);

      final late = await staged(3);
      final outcome = await publish(
        late,
        status: AnimatedArtworkStatus.auto,
        ticket: ticket,
      );
      expect(outcome, AnimatedArtworkSaveOutcome.superseded);
      expect(late.file.existsSync(), isFalse);
      expect((await store.recordFor(album, key))?.status,
          AnimatedArtworkStatus.manual);
    });

    test('a change of mind during the check discards the publication', () async {
      final ticket = store.ticketFor(album, key);
      late Future<void> clearing;
      final outcome = await publish(
        await staged(3),
        status: AnimatedArtworkStatus.auto,
        ticket: ticket,
        mayCommit: () async {
          // Clear starts while the download is being checked. It queues
          // behind this publication, so it is only awaited afterwards.
          clearing = store.clearAll();
          return true;
        },
      );
      await clearing;
      expect(outcome, AnimatedArtworkSaveOutcome.superseded);
      expect(await store.readAll(), isEmpty);
    });

    test('Clear invalidates in-flight publication and removes every video', () async {
      await publish(await staged(3), status: AnimatedArtworkStatus.auto);
      final ticket = store.ticketFor(album, 'other');

      await store.clearAll();
      expect(await store.readAll(), isEmpty);
      expect(await store.sizeBytes(), 0);

      final late = await staged(5);
      final outcome = await publish(
        late,
        status: AnimatedArtworkStatus.auto,
        forKey: 'other',
        ticket: ticket,
      );
      expect(outcome, AnimatedArtworkSaveOutcome.superseded);
      expect(late.file.existsSync(), isFalse);
    });

    test('a manual miss over a video is refused, not recorded', () async {
      await publish(await staged(3), status: AnimatedArtworkStatus.manual);
      final outcome = await store.recordWithoutVideo(
        kind: album,
        key: key,
        status: AnimatedArtworkStatus.notFound,
      );
      expect(outcome, AnimatedArtworkSaveOutcome.kept);
    });
  });
}
