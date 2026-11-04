import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:sistrum/widgets/primitives/app_surface.dart';

void main() {
  for (final sistrum in [true]) {
    testWidgets(
      'confirmation preserves cancel and confirm results (Sistrum: $sistrum)',
      (tester) async {
        bool? result;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: sistrum ? AppTheme.build(Brightness.dark) : ThemeData(),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    child: const Text('Open'),
                    onPressed: () async {
                      result = await showAppDialog<bool>(
                        context: context,
                        builder: (context) => AppAlertDialog(
                          title: const Text('Remove extension'),
                          content: const Text('Remove this example extension?'),
                          actions: [
                            AppDialogAction(
                              isDefault: true,
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            AppDialogAction(
                              filled: true,
                              isDestructive: true,
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          find.byType(AppSurface),
          sistrum ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(AlertDialog),
          sistrum ? findsNothing : findsOneWidget,
        );
        if (sistrum) {
          final remove = find.widgetWithText(CupertinoButton, 'Remove');
          final cancel = find.widgetWithText(CupertinoButton, 'Cancel');
          expect(
            tester.getRect(remove).bottom,
            lessThan(tester.getRect(cancel).top),
          );
          expect(tester.getRect(remove).width, tester.getRect(cancel).width);
          expect(
            DefaultTextStyle.of(
              tester.element(find.text('Remove')),
            ).style.color,
            AppTheme.build(Brightness.dark).colorScheme.primary,
          );
          expect(find.byType(CupertinoAlertDialog), findsNothing);
          expect(find.byType(FilledButton), findsNothing);
        }
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(result, isFalse);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();
        expect(result, isTrue);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('confirmation keeps actions reachable with long text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: AppAlertDialog(
              title: const Text('Delete these tracks from your library?'),
              content: Text(
                List.filled(12, 'This removes the selected files.').join(' '),
              ),
              actions: [
                AppDialogAction(onPressed: () {}, child: const Text('Cancel')),
                AppDialogAction(
                  isDestructive: true,
                  onPressed: () {},
                  child: const Text('Delete from Library'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cancel').hitTestable(), findsOneWidget);
    expect(find.text('Delete from Library').hitTestable(), findsOneWidget);
    final scroll = find.byType(SingleChildScrollView).first;
    await tester.drag(scroll, const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(find.text('Cancel').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
