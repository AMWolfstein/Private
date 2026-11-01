import 'dart:io';
import 'package:flutter/services.dart';
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
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => root.path,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        ),
      );
      final source = await File(
        '${root.path}/track.wav',
      ).writeAsBytes([1, 2, 3]);
      final store = AutoplaySoundStore();
      final stamp = (await store.stamp(source.path))!;
      const profile = AutoplaySoundProfile([0.1, 0.2, 0.7, 0.6, 0.5, 0.4]);
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
      final directory = Directory('${root.path}/autoplay_sound_v1');
      final file = (await directory.list().toList()).whereType<File>().single;
      await file.writeAsString('{incomplete');
      expect(await store.load(source.path), isNull);
      await source.delete();
      expect(await store.load(source.path), isNull);
    },
  );
}
