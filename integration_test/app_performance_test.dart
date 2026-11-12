import 'app_artwork_performance_test.dart' as artwork;
import 'app_lyrics_performance_test.dart' as lyrics;
import 'app_rendering_performance_test.dart' as rendering;
import 'app_screens_performance_test.dart' as screens;
import 'performance_probe.dart';

void main() {
  PerformanceTestBinding.ensureInitialized();
  rendering.main();
  screens.main();
  artwork.main();
  lyrics.main();
}
