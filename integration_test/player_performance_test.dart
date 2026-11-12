import 'material_performance_test.dart' as material;
import 'app_artwork_performance_test.dart' as artwork;
import 'app_lyrics_performance_test.dart' as lyrics;
import 'performance_probe.dart';

/// Compare both player styles with one build and identical shared fixtures.
void main() {
  PerformanceTestBinding.ensureInitialized();
  material.main();
  artwork.main();
  lyrics.main();
}
