import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/screens/settings/logs/log_page.dart';
import 'package:sistrum/utils/logging/logger.dart';
import 'package:sistrum/utils/logging/log_entry.dart';

import '../../support/material_test_theme.dart';

// The eager baseline mounted all 500 rows (initial host build 2,352,268 us).
// Keep the same inventory and viewport to measure lazy row construction. These
// counts and elapsed host-build times are not device frame timings.
void main() {
  testWidgets('disabling autoscroll cancels an in-flight correction', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final buffer = LogBuffer()..clear();
    addTearDown(buffer.clear);
    buffer.addAll([
      for (var index = 0; index < LogBuffer.maxEntries; index++)
        LogEntry(
          timestamp: DateTime(2026, 1, 1).add(Duration(seconds: index)),
          level: 'ERROR',
          tag: 'AutoScroll',
          message: 'Row $index',
        ),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: MaterialTestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LogPage(),
        ),
      ),
    );
    buffer.add(
      LogEntry(
        timestamp: DateTime(2026, 1, 1, 1),
        level: 'ERROR',
        tag: 'AutoScroll',
        message: 'First append',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    // Exercise the wired control while the floating toolbar is moving during
    // the scroll animation; a coordinate tap can miss that moving target.
    tester
        .widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.vertical_align_bottom),
        )
        .onPressed!();
    await tester.pump();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    final stoppedAt = position.pixels;
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(stoppedAt, 0.5));
    buffer.add(
      LogEntry(
        timestamp: DateTime(2026, 1, 1, 2),
        level: 'ERROR',
        tag: 'AutoScroll',
        message: 'Second append',
      ),
    );
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(stoppedAt, 0.5));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('autoscroll reaches newest mixed-height log from the top', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final buffer = LogBuffer()..clear();
    addTearDown(buffer.clear);
    buffer.addAll([
      for (var index = 0; index < LogBuffer.maxEntries; index++)
        LogEntry(
          timestamp: DateTime(2026, 1, 1).add(Duration(seconds: index)),
          level: 'ERROR',
          tag: 'AutoScroll',
          // Short initial rows underestimate the extent of later tall rows.
          message:
              'Row $index: ${List.filled(index < 100 ? 1 : index % 9 + 5, 'line').join('\n')}',
        ),
    ]);
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: MaterialTestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LogPage(),
        ),
      ),
    );
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(position.pixels, 0);
    buffer.add(
      LogEntry(
        timestamp: DateTime(2026, 1, 1, 1),
        level: 'ERROR',
        tag: 'AutoScroll',
        message: 'LATEST APPENDED ROW',
      ),
    );
    await tester.pumpAndSettle();
    // ignore: avoid_print
    print(
      'UI-401 autoscroll: pixels=${position.pixels}, '
      'max=${position.maxScrollExtent}',
    );
    expect(find.text('LATEST APPENDED ROW').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('500-entry log list build measurement', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final buffer = LogBuffer()..clear();
    addTearDown(buffer.clear);
    buffer.addAll([
      for (var index = 0; index < LogBuffer.maxEntries; index++)
        LogEntry(
          timestamp: DateTime(2026, 1, 1).add(Duration(seconds: index)),
          level: 'ERROR',
          tag: 'Measurement',
          message: 'Log entry $index',
        ),
    ]);
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final stopwatch = Stopwatch()..start();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: MaterialTestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LogPage(),
        ),
      ),
    );
    stopwatch.stop();
    final mountedRows = find
        .byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == 'LogEntryTile',
        )
        .evaluate()
        .length;
    // ignore: avoid_print
    print(
      'UI-401: initial mounted rows=$mountedRows, '
      'host build microseconds=${stopwatch.elapsedMicroseconds}',
    );
    expect(buffer.length, LogBuffer.maxEntries);
    expect(mountedRows, greaterThan(0));
    expect(mountedRows, lessThan(80));
    await tester.scrollUntilVisible(
      find.text('Log entry 499'),
      5000,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 20,
    );
    await tester.pumpAndSettle();
    expect(find.text('Log entry 499').hitTestable(), findsOneWidget);
    await tester.longPress(find.text('Log entry 499').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
