import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/utils/detail_page_route.dart';

void main() {
  test('album identity ignores case and surrounding spaces', () {
    final a = DetailPage.album('Blue Hour ', artistName: 'Ada');
    final b = DetailPage.album('blue hour', artistName: ' ADA');
    expect(a.matches(b), isTrue);
    expect(a.kind, 'album');
  });

  test('albums with different artists are different pages', () {
    final a = DetailPage.album('Blue Hour', artistName: 'Ada');
    final b = DetailPage.album('Blue Hour', artistName: 'Ben');
    expect(a.matches(b), isFalse);
  });

  testWidgets('a route marked with its page is found on top', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final page = DetailPage.album('Blue Hour', artistName: 'Ada');
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Builder(
          builder: (context) {
            DetailPage.mark(context, page);
            return const Scaffold(body: Text('Album'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      DetailPage.isOnTop(
        navigatorKey.currentState!,
        DetailPage.album('blue hour', artistName: 'ada'),
      ),
      isTrue,
    );
    expect(
      DetailPage.isOnTop(
        navigatorKey.currentState!,
        DetailPage.album('Other', artistName: 'Ada'),
      ),
      isFalse,
    );
  });

  testWidgets('a page that is not on top is not reported as on top', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final page = DetailPage.album('Blue Hour', artistName: 'Ada');
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Builder(
          builder: (context) {
            DetailPage.mark(context, page);
            return const Scaffold(body: Text('Album'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Unmarked')),
      ),
    );
    await tester.pumpAndSettle();
    expect(DetailPage.isOnTop(navigatorKey.currentState!, page), isFalse);
  });
}
