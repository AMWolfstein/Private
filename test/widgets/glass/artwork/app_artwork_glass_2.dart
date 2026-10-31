part of 'app_artwork_glass_test.dart';

void _registerAppArtworkGlass2() {
  testWidgets('grounds are released with their screen and within budget', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(child: _Player(source: null, insetKey: GlobalKey())),
    );
    final ground = _playerGround(tester);
    await _settle(tester, () => ground.hasGround);
    expect(AppGroundBudget.bytes, greaterThan(0));
    expect(AppGroundBudget.bytes, lessThanOrEqualTo(AppGroundBudget.maxBytes));
    await tester.pumpWidget(const SizedBox());
    expect(AppGroundBudget.bytes, 0);
    expect(AppGroundBudget.owners, 0);

    // Past the cap, the least recently painted page ground is released.
    final images = <ui.Image>[];
    Future<AppGround> ground1536() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawPaint(Paint());
      final image = (await tester.runAsync(
        () => recorder.endRecording().toImage(384, 1024),
      ))!;
      images.add(image);
      return AppGround(image, edge: Colors.black);
    }

    final pages = [
      for (var i = 0; i < 5; i++)
        AppGroundController(vsync: const TestVSync(), rectOf: () => null),
    ];
    for (final page in pages) {
      page
        ..show(await ground1536())
        ..markPainted();
    }
    expect(AppGroundBudget.bytes, lessThanOrEqualTo(AppGroundBudget.maxBytes));
    expect(pages.first.hasGround, isFalse);
    expect(pages.last.hasGround, isTrue);
    for (final page in pages) {
      page.dispose();
    }
    expect(AppGroundBudget.bytes, 0);
  });
}
