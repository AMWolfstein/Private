import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_warmup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('warming up glass completes without blocking the app', (
    tester,
  ) async {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    // Preparation is optional, so it must finish quickly whether or not the
    // device supports the shader filter.
    await tester.runAsync(
      () => AppGlassWarmup.prepare(view).timeout(const Duration(seconds: 10)),
    );
    expect(tester.takeException(), isNull);
  });
}
