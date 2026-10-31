part of 'music_player_runtime_test.dart';

void _registerMusicPlayerRuntime4() {
  test(
    'provider scopes isolate transport settings and notification favorites',
    () async {
      final firstDecks = <_Deck>[];
      final secondDecks = <_Deck>[];
      final first = _runtime(
        decks: firstDecks,
        settings: const AppSettings(
          pauseOnMute: false,
          playbackNormalization: true,
        ),
      );
      final second = _runtime(
        decks: secondDecks,
        settings: const AppSettings(
          pauseOnMute: false,
          usbBitPerfect: true,
          usbDirect: true,
          usbDsdOverPcm: true,
          usbAllowFixedVolume: true,
          dapExclusive: true,
        ),
      );
      final containers = [
        for (final runtime in [first, second])
          ProviderContainer(
            overrides: [musicPlayerRuntimeProvider.overrideWithValue(runtime)],
          ),
      ];
      for (final container in containers) {
        addTearDown(container.dispose);
        await container.read(musicPlayerControllerProvider).playAll([_track]);
      }
      expect(firstDecks.single.state, PlayerState.playing);
      expect(secondDecks.single.state, PlayerState.playing);
      expect(firstDecks.single.volumes.last, closeTo(0.501, 0.001));
      expect(secondDecks.single.volumes.last, 1);
      expect(firstDecks.single.outputOptions!.values, everyElement(isFalse));
      expect(secondDecks.single.outputOptions!.values, everyElement(isTrue));
      final toggled = <String>[];
      first.configureNotification(
        presentation: const PlaybackNotification(sistrum: true),
        toggleFavorite: (item) async {
          toggled.add('first:${item.id}');
          return true;
        },
      );
      second.configureNotification(
        presentation: const PlaybackNotification(sistrum: true),
        toggleFavorite: (item) async {
          toggled.add('second:${item.id}');
          return false;
        },
      );
      await first.handler!.customAction(PlaybackNotification.favoriteAction);
      expect(first.notification.loved, isTrue);
      expect(second.notification.loved, isFalse);
      await second.handler!.customAction(PlaybackNotification.favoriteAction);
      expect(toggled, ['first:one', 'second:one']);
      expect(
        first.handler!.playbackState.value.controls.first.label,
        'Remove from favorites',
      );
      expect(
        second.handler!.playbackState.value.controls.first.label,
        'Favorite',
      );
      first.configure(first.settings.copyWith(playbackNormalizationPreamp: -6));
      await _settle();
      expect(firstDecks.single.volumes.last, closeTo(0.251, 0.001));
      first.configure(first.settings.copyWith(playbackNormalization: false));
      await _settle();
      expect(firstDecks.single.volumes.last, 1);
      expect(second.settings.usbBitPerfect, isTrue);
      expect(secondDecks.single.volumes, [1]);
    },
  );
}
