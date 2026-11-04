import 'app_artwork_performance_test.dart' as artwork;
import 'app_lyrics_performance_test.dart' as lyrics;
import 'performance_probe.dart';

void main() {
  PerformanceTestBinding.ensureInitialized();
  artwork.main();
  lyrics.main();
}
