import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/widgets/player/player_queue_dismissible.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final direction in TextDirection.values) {
      testWidgets(
        'Sistrum queue swipe expands and follows $brightness $direction',
        (tester) async {
          var removals = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: SistrumTheme.build(brightness),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Directionality(
                textDirection: direction,
                child: Scaffold(
                  body: Center(
                    child: PlayerQueueDismissible(
                      onRemove: () => removals++,
                      child: const SizedBox(
                        key: ValueKey('song'),
                        width: 320,
                        height: 64,
                        child: Text('Queued song'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          final song = find.byKey(const ValueKey('song'));
          final original = tester.getRect(song);
          final sign = direction == TextDirection.ltr ? -1.0 : 1.0;
          final icon = find.byIcon(CupertinoIcons.trash);
          final gesture = await tester.startGesture(original.center);
          await gesture.moveBy(Offset(sign * 20, 0));
          await gesture.moveBy(Offset(sign * 80, 0));
          await tester.pump();

          final background = find
              .ancestor(of: icon, matching: find.byType(DecoratedBox))
              .first;
          expect(tester.getRect(background), original);
          final decoration = tester.widget<DecoratedBox>(background).decoration;
          expect(
            (decoration as BoxDecoration).color,
            CupertinoColors.systemRed.resolveFrom(tester.element(icon)),
          );
          expect(decoration.borderRadius, BorderRadius.circular(16));
          final shifted = tester.getRect(song);
          final exposedCenter = direction == TextDirection.ltr
              ? (shifted.right + original.right) / 2
              : (shifted.left + original.left) / 2;
          expect(tester.getCenter(icon).dx, closeTo(exposedCenter, 0.1));

          // A short, slow swipe returns to the row without removing it.
          await tester.pump(const Duration(milliseconds: 300));
          await gesture.up();
          await tester.pumpAndSettle();
          expect(removals, 0);
          expect(tester.getRect(song), original);
          expect(icon.hitTestable(), findsNothing);

          final fullSwipe = await tester.startGesture(original.center);
          await fullSwipe.moveBy(Offset(sign * 20, 0));
          await fullSwipe.moveBy(Offset(sign * 256, 0));
          await tester.pump();
          final edge = direction == TextDirection.ltr
              ? tester.getRect(song).right
              : tester.getRect(song).left;
          expect(tester.getCenter(icon).dx, closeTo(edge - sign * 36, 0.1));
          expect(tester.getCenter(icon).dy, original.center.dy);
          expect(removals, 0);

          await fullSwipe.up();
          await tester.pumpAndSettle();
          expect(removals, 1);
          // If the queue update is deferred/rejected, the row remains usable.
          expect(tester.getRect(song), original);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('queued rows offer a Remove semantic action', (tester) async {
    var removals = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: SistrumTheme.build(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: PlayerQueueDismissible(
              onRemove: () => removals++,
              child: const SizedBox(width: 320, height: 64),
            ),
          ),
        ),
      ),
    );

    final semantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.customSemanticsActions != null &&
            widget.properties.customSemanticsActions!.isNotEmpty,
      ),
    );
    final actions = semantics.properties.customSemanticsActions!;
    expect(actions.keys.single.label, 'Remove');
    actions.values.single();
    expect(removals, 1);
  });

  testWidgets('a disabled row offers no Remove action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SistrumTheme.build(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: PlayerQueueDismissible(
              onRemove: () {},
              enabled: false,
              child: const SizedBox(width: 320, height: 64),
            ),
          ),
        ),
      ),
    );
    final semantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.customSemanticsActions != null,
      ),
    );
    expect(semantics.properties.customSemanticsActions, isEmpty);
  });
}
