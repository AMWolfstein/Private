part of 'music_player_automix.dart';

extension MusicAutoMixPart2 on MusicAutoMix {
  Set<String> get pinnedPaths => {
    ..._mixPins,
    for (final paths in _preparationPins.values) ...paths,
  };
}
