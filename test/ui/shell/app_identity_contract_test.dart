import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/constants/app_info.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/services/backup/backup_service.dart';
import 'package:sistrum/services/playback/music_player/music_player_runtime.dart';
import 'package:sistrum/services/playback/notification/playback_notification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Sistrum playback uses the matching native identity and small icon', () {
    expect(AppInfo.appName, 'Sistrum');
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

  test('new backups and notification actions use the canonical identity', () {
    expect(BackupService.magic, 'sistrum-backup');
    expect(BackupService.fileExtension, 'sbk');
    expect(PlaybackNotification.favoriteAction, 'sistrum.favorite');
    expect(PlaybackNotification.shuffleAction, 'sistrum.shuffle');
  });

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
          expect(
            text,
            isNot(
              contains(
                '\u0053\u0070\u006f\u0074\u0069\u0046\u004c\u0041\u0043',
              ),
            ),
          );
        }
      },
    );
  }
}
