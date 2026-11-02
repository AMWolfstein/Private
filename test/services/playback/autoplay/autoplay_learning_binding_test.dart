import 'package:sistrum/services/playback/autoplay/autoplay_taste.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sistrum/services/playback/autoplay/autoplay_ranker.dart';
import 'package:sistrum/services/playback/music_player/music_player_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/services/playback/autoplay/autoplay_personalization.dart';
import 'package:sistrum/core/models/track.dart';
import 'package:sistrum/providers/library/library_preference_events_provider.dart';
import 'package:sistrum/providers/playback/autoplay_learning_provider.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/services/library/collections/library_preference_events.dart';
import '../../../support/music_player_harness.dart';

class LearningSettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
  void enable(bool value) =>
      state = state.copyWith(autoplayPersonalization: value);
}

void main() {
  test(
    'runtime routes remembered-pick feedback and reset clears both learners',
    () async {
      sqfliteFfiInit();
      final db = await AutoplayRanker.openWithFactory(
        databaseFactoryFfi,
        inMemoryDatabasePath,
      );
      addTearDown(db.close);
      final ranker = AutoplayRanker(open: () async => db);
      final tasteDb = await AutoplayTaste.openWithFactory(
        databaseFactoryFfi,
        inMemoryDatabasePath,
      );
      addTearDown(tasteDb.close);
      final runtime = musicPlayerRuntimeFor(
        createRanker: () => ranker,
        createTaste: () => AutoplayTaste(open: () async => tasteDb),
        createPersonalization: () =>
            AutoplayPersonalization(load: () async => null, save: (_) async {}),
      );
      final learning = runtime.personalization;
      learning.setEnabled(true);
      await learning.ensureLoaded();
      ranker.remember('/picked.flac', {'genre': 4});
      const picked = AutoplayLearningTrack(
        source: '/picked.flac',
        title: 'Picked',
        artist: 'Artist',
      );
      learning.endorse(picked, AutoplayFeedbackKind.loved);
      await Future<void>.delayed(Duration.zero);
      expect(await ranker.readOutcomes(), hasLength(1));
      expect(learning.observations, 1);
      learning.endorse(
        const AutoplayLearningTrack(
          source: '/manual.flac',
          title: 'Manual',
          artist: 'Artist',
        ),
        AutoplayFeedbackKind.loved,
      );
      await Future<void>.delayed(Duration.zero);
      expect(await ranker.readOutcomes(), hasLength(1));
      runtime.configure(
        runtime.settings.copyWith(autoplayPersonalization: false),
      );
      learning.setEnabled(false);
      ranker.remember('/off.flac', {'genre': 4});
      learning.endorse(
        const AutoplayLearningTrack(
          source: '/off.flac',
          title: 'Off',
          artist: 'Artist',
        ),
        AutoplayFeedbackKind.loved,
      );
      await Future<void>.delayed(Duration.zero);
      expect(await ranker.readOutcomes(), hasLength(1));
      await resetAutoplayLearning(runtime: runtime);
      expect(learning.observations, 0);
      expect(await ranker.readOutcomes(), isEmpty);
      expect(ranker.evaluation.value?.outcomes, 0);
      expect(runtime.handler, isNull);
    },
  );

  test(
    'explicit feedback is scoped, respects opt-out and never starts a player',
    () async {
      final runtime = musicPlayerRuntimeFor(
        createPersonalization: () =>
            AutoplayPersonalization(load: () async => null, save: (_) async {}),
      );
      final container = ProviderContainer(
        overrides: [
          musicPlayerRuntimeProvider.overrideWithValue(runtime),
          settingsProvider.overrideWith(LearningSettings.new),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        autoplayLearningProvider,
        (_, _) {},
      );
      await runtime.personalization.ensureLoaded();
      final events = container.read(libraryPreferenceEventsProvider);
      const track = Track(
        id: 'one',
        name: 'One',
        artistName: 'Artist',
        albumName: 'Album',
        duration: 120,
      );
      events.publish(track, LibraryPreferenceKind.loved);
      expect(runtime.personalization.observations, 1);
      expect(runtime.handler, isNull);
      (container.read(settingsProvider.notifier) as LearningSettings).enable(
        false,
      );
      container.read(autoplayLearningProvider);
      events.publish(track, LibraryPreferenceKind.playlisted);
      expect(runtime.personalization.observations, 1);
      subscription.close();
      await container.pump();
      events.publish(track, LibraryPreferenceKind.loved);
      expect(runtime.personalization.observations, 1);
      expect(runtime.handler, isNull);
    },
  );
}
