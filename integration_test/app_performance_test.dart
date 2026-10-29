import 'app_artwork_performance_test.dart' as artwork;
import 'app_lyrics_performance_test.dart' as lyrics;
import 'app_rendering_performance_test.dart' as rendering;
import 'performance_probe.dart';

void main() {
  PerformanceTestBinding.ensureInitialized();
  rendering.main();
  artwork.main();
  lyrics.main();
}
