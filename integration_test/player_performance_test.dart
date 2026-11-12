import 'app_artwork_performance_test.dart' as artwork;
import 'app_lyrics_performance_test.dart' as lyrics;
import 'app_seek_performance_test.dart' as seek;
import 'performance_probe.dart';

/// Runs the player's seek, artwork and lyrics scenarios in one build.
void main() {
  PerformanceTestBinding.ensureInitialized();
  seek.main();
  artwork.main();
  lyrics.main();
}
