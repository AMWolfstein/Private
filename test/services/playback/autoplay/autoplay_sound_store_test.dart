import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sistrum/services/playback/autoplay/song_analysis_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/playback/autoplay/autoplay_sound_profile.dart';
import 'package:sistrum/services/playback/autoplay/autoplay_sound_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cached profiles reject edited/deleted audio and incomplete writes',
    () async {
      final root = await Directory.systemTemp.createTemp('sound-store-test-');
      addTearDown(() => root.delete(recursive: true));
      sqfliteFfiInit();
      final database = await SongAnalysisStore.openWithFactory(
        databaseFactoryFfi,
        '${root.path}/analysis.db',
      );
      addTearDown(database.close);
      final source = await File(
        '${root.path}/track.wav',
      ).writeAsBytes([1, 2, 3]);
      final store = AutoplaySoundStore(
        store: SongAnalysisStore(open: () async => database),
      );
      final stamp = (await store.stamp(source.path))!;
      final profile = AutoplaySoundProfile(List.filled(42, 0.0));
      expect(await store.load(source.path), isNull);
      await store.save(source.path, profile, stamp);
      expect((await store.load(source.path))!.values, profile.values);
      await source.writeAsBytes([1, 2, 3, 4]);
      expect(await store.load(source.path), isNull);
      await store.save(
        source.path,
        profile,
        stamp,
      ); // Stale analysis cannot overwrite.
      expect(await store.load(source.path), isNull);
      final fresh = (await store.stamp(source.path))!;
      await store.save(source.path, profile, fresh);
      await database.execute("UPDATE song_features SET features = x'00'");
      expect(await store.load(source.path), isNull);
      await source.delete();
      expect(await store.load(source.path), isNull);
    },
  );
}
