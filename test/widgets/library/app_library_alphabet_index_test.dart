import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/library/app_library_alphabet_index.dart';
import 'package:sistrum/widgets/library/library_section_list.dart';

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('letter rail supports tap drag and RTL ($direction)', (
      tester,
    ) async {
      final selected = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: AppLibraryAlphabetIndex(
                labels: const ['A', 'B', 'أ', 'م'],
                onSelected: selected.add,
                child: const Center(child: Text('Library')),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getCenter(find.text('B')).dx,
        greaterThan(
          tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
        ),
      );
      await tester.tap(find.text('B'));
      await tester.pump();
      expect(selected, ['B']);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('A')),
      );
      await gesture.moveTo(tester.getCenter(find.text('م')));
      await gesture.up();
      await tester.pump();
      expect(selected.last, 'م');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets(
    'index seeks an unbuilt row across lazy variable-height sections',
    (tester) async {
      final controller = AppLibrarySectionController();
      final items = List.generate(1500, (i) => 'Song $i');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 180)),
                SectionedLibrarySliverList<String>(
                  controller: controller,
                  items: items,
                  groupingKey: 'test',
                  labelOf: (item) => 'Group ${items.indexOf(item) ~/ 50}',
                  rowBuilder: (_, i) => SizedBox(
                    height: i % 3 == 0 ? 82 : 55,
                    child: Text(items[i]),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final seek = controller.reveal(1240);
      await tester.pumpAndSettle();
      expect(await seek, isTrue);
      expect(find.text('Song 1240').hitTestable(), findsOneWidget);
      final backward = controller.reveal(10);
      await tester.pumpAndSettle();
      expect(await backward, isTrue);
      expect(find.text('Song 10').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
