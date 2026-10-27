import 'sistrum_artwork_performance_test.dart' as artwork;
import 'sistrum_lyrics_performance_test.dart' as lyrics;
import 'sistrum_rendering_performance_test.dart' as rendering;
import 'performance_probe.dart';

void main() {
  PerformanceTestBinding.ensureInitialized();
  rendering.main();
  artwork.main();
  lyrics.main();
}
