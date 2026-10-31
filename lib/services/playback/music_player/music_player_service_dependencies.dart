part of 'music_player_service.dart';

extension _MusicPlayerHandlerPart1 on MusicPlayerHandler {
  PlaybackDependencies get _dependencies => _runtime.dependencies;
  AppSettings get _settings => _runtime.settings;
}
