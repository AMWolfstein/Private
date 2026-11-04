import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/glass/debug/app_artist_glass_isolation.dart';

void main() {
  test('the video band defaults to live and toggles without persisting', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(appArtistVideoBandProvider), AppArtistVideoBand.live);
    final epoch = appDiagnosticWindowEpoch.value;
    container.read(appArtistVideoBandProvider.notifier).toggle();
    expect(
      container.read(appArtistVideoBandProvider),
      AppArtistVideoBand.still,
    );
    // A change restarts the HUD's measurement window.
    expect(appDiagnosticWindowEpoch.value, epoch + 1);
    container.read(appArtistVideoBandProvider.notifier).toggle();
    expect(container.read(appArtistVideoBandProvider), AppArtistVideoBand.live);
  });
}
