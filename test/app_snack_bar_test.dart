import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/primitives/app_snack_bar.dart';
import 'package:sistrum/widgets/glass/app_chrome.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('snackbar retains backdrop color during entry in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final capture = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.build(brightness),
            builder: (_, child) => RepaintBoundary(
              key: capture,
              child: AppScaffoldMessenger(child: child!),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: ColoredBox(color: Colors.blue)),
                        Expanded(child: ColoredBox(color: Colors.red)),
                      ],
                    ),
                    Center(
                      child: TextButton(
                        onPressed: () => showAppSnackBar(
                          context,
                          content: const Text('Extension installed'),
                        ),
                        child: const Text('Show'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Show'));
      await tester.pump();
      for (final elapsed in [16, 80, 250]) {
        await tester.pump(Duration(milliseconds: elapsed));
        final rect = tester.getRect(find.byType(AppGlassPanel));
        final colors = await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(capture),
          );
          final image = await boundary.toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final colors = <Color>[];
          for (final fraction in [0.25, 0.75]) {
            final x = (rect.left + rect.width * fraction).floor();
            final y = (rect.bottom - 8).floor();
            final offset = (y * image.width + x) * 4;
            colors.add(
              Color.fromARGB(
                bytes.getUint8(offset + 3),
                bytes.getUint8(offset),
                bytes.getUint8(offset + 1),
                bytes.getUint8(offset + 2),
              ),
            );
          }
          image.dispose();
          return colors;
        });
        // The painted dark tint attenuates chroma along with luminance. Both
        // backdrop hues must remain visibly distinct throughout the transition.
        expect(colors![0].b - colors[0].r, greaterThan(0.16));
        expect(colors[1].r - colors[1].b, greaterThan(0.16));
        final foreground = AppTheme.build(brightness).colorScheme.onSurface;
        for (final background in colors) {
          final luminances = [
            foreground.computeLuminance(),
            background.computeLuminance(),
          ]..sort();
          expect(
            (luminances.last + 0.05) / (luminances.first + 0.05),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final sistrum in [true]) {
    testWidgets(
      'new messages replace old ones and still dismiss (Sistrum: $sistrum)',
      (tester) async {
        late BuildContext messageContext;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: sistrum ? AppTheme.build(Brightness.dark) : ThemeData(),
              builder: (_, child) => AppScaffoldMessenger(child: child!),
              home: Builder(
                builder: (context) {
                  messageContext = context;
                  return const Scaffold(body: SizedBox.expand());
                },
              ),
            ),
          ),
        );
        final first = showAppSnackBar(
          messageContext,
          content: const Text('First'),
          duration: const Duration(seconds: 1),
        );
        await tester.pumpAndSettle();
        expect(find.text('First'), findsOneWidget);
        final second = showAppSnackBar(
          messageContext,
          content: const Text('Second'),
        );
        await tester.pumpAndSettle();
        expect(await first.closed, SnackBarClosedReason.remove);
        expect(find.text('First'), findsNothing);
        expect(find.text('Second'), findsOneWidget);
        await tester.drag(find.text('Second'), const Offset(0, 300));
        await tester.pumpAndSettle();
        expect(await second.closed, SnackBarClosedReason.swipe);
        expect(find.text('Second'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('rapid messages never leave a backlog or persist an action', (
    tester,
  ) async {
    late BuildContext messageContext;
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => AppScaffoldMessenger(child: child!),
        home: Builder(
          builder: (context) {
            messageContext = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );
    final controllers = [
      for (var i = 0; i < 10; i++)
        ScaffoldMessenger.of(messageContext).showSnackBar(
          SnackBar(
            content: Text('Message $i'),
            action: SnackBarAction(label: 'Action', onPressed: () {}),
            duration: const Duration(minutes: 1),
          ),
        ),
    ];
    await tester.pumpAndSettle();
    expect(find.text('Message 9'), findsOneWidget);
    expect(find.text('Message 0'), findsNothing);
    for (final controller in controllers.take(9)) {
      expect(await controller.closed, SnackBarClosedReason.remove);
    }
    await tester.pump(kAppSnackBarLongestDuration);
    await tester.pumpAndSettle();
    expect(await controllers.last.closed, SnackBarClosedReason.timeout);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('ordinary messages close in 3 s; longer requests keep up to 8 s', () {
    expect(
      appSnackBarDuration(const Duration(seconds: 4)),
      kAppSnackBarDuration,
    );
    expect(
      appSnackBarDuration(const Duration(seconds: 2)),
      const Duration(seconds: 2),
    );
    expect(
      appSnackBarDuration(const Duration(seconds: 6)),
      const Duration(seconds: 6),
    );
    expect(
      appSnackBarDuration(const Duration(seconds: 8)),
      kAppSnackBarLongestDuration,
    );
    expect(
      appSnackBarDuration(const Duration(minutes: 1)),
      kAppSnackBarLongestDuration,
    );
  });

  testWidgets('a 6 s restart hint stays past 3 s', (tester) async {
    late BuildContext messageContext;
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => AppScaffoldMessenger(child: child!),
        home: Builder(
          builder: (context) {
            messageContext = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );
    ScaffoldMessenger.of(messageContext).showSnackBar(
      const SnackBar(content: Text('Restart'), duration: Duration(seconds: 6)),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Restart'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Restart'), findsNothing);
  });
}
