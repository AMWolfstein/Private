import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/constants/app_info.dart';
import 'package:spotiflac_android/l10n/app_localizations.dart';
import 'package:spotiflac_android/services/backup_service.dart';
import 'package:spotiflac_android/services/music_player_runtime.dart';
import 'package:spotiflac_android/services/playback_notification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Sistrum playback uses the matching native identity and small icon', () {
    expect(AppInfo.appName, 'Sistrum');
    expect(
      const PlaybackDependencies().notificationChannel.name,
      'com.amwolfstein.sistrum/playback_notification',
    );
    const config = PlaybackDependencies.notificationConfig;
    expect(
      config.androidNotificationChannelId,
      'com.amwolfstein.sistrum.playback',
    );
    expect(config.androidNotificationIcon, 'drawable/ic_stat_sistrum');
    expect(config.androidNotificationChannelName, 'Playback');
    expect(config.androidNotificationOngoing, isTrue);
    expect(config.androidStopForegroundOnPause, isTrue);
  });

  test(
    'persisted backup and notification action identities stay compatible',
    () {
      expect(BackupService.magic, 'spotiflac-backup');
      expect(BackupService.fileExtension, 'sflb');
      expect(PlaybackNotification.favoriteAction, 'spotiflac.favorite');
      expect(PlaybackNotification.shuffleAction, 'spotiflac.shuffle');
    },
  );

  for (final locale in AppLocalizations.supportedLocales) {
    test(
      'current app copy uses Sistrum in ${locale.toLanguageTag()}',
      () async {
        final strings = await AppLocalizations.delegate.load(locale);
        expect(strings.appName, 'Sistrum');
        for (final text in [
          strings.usbVolumeWarning,
          strings.libraryRemoveFolderMessage,
          strings.libraryStorageAccessMessage,
          strings.backupInvalidFile,
          strings.audioInfoPlayerValue,
        ]) {
          expect(text, contains('Sistrum'));
          expect(text, isNot(contains('SpotiFLAC')));
        }
      },
    );
  }
}
