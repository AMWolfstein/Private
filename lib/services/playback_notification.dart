import 'package:audio_service/audio_service.dart';

/// Presentation only; every transport action still uses the audio handler.
class PlaybackNotification {
  static const favoriteAction = 'sistrum.favorite';
  static const shuffleAction = 'sistrum.shuffle';

  final bool sistrum;
  final String? mediaId;
  final String? source;
  final bool loved;
  final String favoriteLabel;
  final String unfavoriteLabel;
  final String shuffleOnLabel;
  final String shuffleOffLabel;

  const PlaybackNotification({
    this.sistrum = false,
    this.mediaId,
    this.source,
    this.loved = false,
    this.favoriteLabel = 'Favorite',
    this.unfavoriteLabel = 'Remove from favorites',
    this.shuffleOnLabel = 'Shuffle on',
    this.shuffleOffLabel = 'Shuffle off',
  });

  String get favoriteActionLabel => loved ? unfavoriteLabel : favoriteLabel;

  PlaybackNotification withFavorite(MediaItem item, bool loved) =>
      PlaybackNotification(
        sistrum: sistrum,
        mediaId: item.id,
        source: item.extras?['source']?.toString(),
        loved: loved,
        favoriteLabel: favoriteLabel,
        unfavoriteLabel: unfavoriteLabel,
        shuffleOnLabel: shuffleOnLabel,
        shuffleOffLabel: shuffleOffLabel,
      );

  List<MediaControl> controls({
    required bool playing,
    required MediaItem? item,
    bool shuffle = false,
  }) {
    if (!sistrum) {
      return [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ];
    }
    final current = item?.id == mediaId && item?.extras?['source'] == source;
    return [
      MediaControl.custom(
        name: favoriteAction,
        androidIcon: current && loved
            ? 'drawable/ic_notification_heart_filled'
            : 'drawable/ic_notification_heart',
        label: current && loved ? unfavoriteLabel : favoriteLabel,
      ),
      MediaControl.skipToPrevious.copyWith(
        androidIcon: 'drawable/ic_widget_previous',
      ),
      (playing ? MediaControl.pause : MediaControl.play).copyWith(
        androidIcon: playing
            ? 'drawable/ic_widget_pause'
            : 'drawable/ic_widget_play',
      ),
      MediaControl.skipToNext.copyWith(androidIcon: 'drawable/ic_widget_next'),
      MediaControl.custom(
        name: shuffleAction,
        androidIcon: shuffle
            ? 'drawable/ic_notification_shuffle_on'
            : 'drawable/ic_notification_shuffle',
        label: shuffle ? shuffleOnLabel : shuffleOffLabel,
      ),
    ];
  }
}
