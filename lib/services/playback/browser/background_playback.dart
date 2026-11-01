import 'package:sistrum/services/playback/music_player/music_player_runtime.dart';
import 'package:sistrum/services/playback/browser/background_favorites.dart';
import 'package:sistrum/services/playback/notification/playback_notification.dart';
import 'package:sistrum/l10n/supported_locales.dart';

/// Safe before Activity attachment. The shared engine already owns playback
/// channels; UI-only startup continues to wait for the Activity separately.
Future<void> initializeMediaBrowser(MusicPlayerRuntime runtime) async {
  final strings = appLocalizationsFor(runtime.settings.locale);
  runtime.updateStrings(
    unknownTitle: strings.unknownTitle,
    unknownArtist: strings.unknownArtist,
  );
  runtime.configureBackgroundNotification(
    presentation: PlaybackNotification(
      sistrum: true,
      favoriteLabel: strings.trackOptionAddToLoved,
      unfavoriteLabel: strings.trackOptionRemoveFromLoved,
      shuffleOnLabel: strings.nowPlayingShuffleOn,
      shuffleOffLabel: strings.nowPlayingPlayInOrder,
    ),
    favorites: BackgroundFavorites(
      library: runtime.dependencies.libraryDatabase,
      collections: runtime.dependencies.collectionsDatabase,
    ),
  );
  await runtime.restoreSession();
  await runtime.initialize();
}
