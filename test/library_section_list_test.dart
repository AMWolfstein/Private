import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sistrum/widgets/library/library_section_list.dart';

void main() {
  test('section initials preserve Unicode graphemes and bucket symbols', () {
    expect(librarySectionInitial('  أغنية'), 'أ');
    expect(librarySectionInitial('éclair'), 'É');
    expect(librarySectionInitial('🎵 song'), '#');
    expect(librarySectionInitial('123'), '#');
    expect(librarySectionInitial(''), '#');
  });
  test('month labels retain each locale across repeated queries', () async {
    await initializeDateFormatting('fr');
    final date = DateTime(2026, 10);
    expect(librarySectionMonth(date, 'en'), 'October 2026');
    expect(librarySectionMonth(date, 'fr'), 'octobre 2026');
    expect(librarySectionMonth(date, 'en'), 'October 2026');
  });
  testWidgets('paging extends a group without duplicate headers or lost rows', (
    tester,
  ) async {
    Widget host(List<String> items) => MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SectionedLibrarySliverList<String>(
              items: items,
              groupingKey: 'title',
              labelOf: librarySectionInitial,
              rowBuilder: (context, index) =>
                  SizedBox(height: 48, child: Text(items[index])),
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(host(['Alpha', 'Apple', 'Beta']));
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    await tester.pumpWidget(
      host(['Alpha', 'Apple', 'Beta', 'Bravo', 'Charlie']),
    );
    for (final text in [
      'A',
      'B',
      'C',
      'Alpha',
      'Apple',
      'Beta',
      'Bravo',
      'Charlie',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
