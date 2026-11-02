import 'dart:async';
import 'package:sistrum/providers/library/local_library_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/services/playback/autoplay/song_analysis.dart';

final songAnalysisProvider = Provider.autoDispose<SongAnalysis>((ref) {
  final analysis = ref.watch(musicPlayerRuntimeProvider).songAnalysis;
  ref.listen(
    settingsProvider,
    (_, settings) => analysis.configure(settings),
    fireImmediately: true,
  );
  ref.listen(localLibraryProvider.select((state) => state.loadedIndexVersion), (
    _,
    _,
  ) {
    unawaited(analysis.refreshProgress());
  });
  unawaited(analysis.refreshProgress());
  return analysis;
});
