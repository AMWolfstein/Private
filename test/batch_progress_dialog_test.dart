import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/batch_progress_dialog.dart';

void main() {
  late GlobalKey<NavigatorState> navigator;
  late BuildContext pageContext;

  Future<void> mount(WidgetTester tester) async {
    navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          navigatorKey: navigator,
          theme: MornyeTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: Text('Home')),
        ),
      ),
    );
    navigator.currentState!.push<void>(
      MaterialPageRoute(
        builder: (context) {
          pageContext = context;
          return const Scaffold(body: Text('Songs'));
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  VoidCallback show({VoidCallback? onCancel}) => BatchProgressDialog.show(
    context: pageContext,
    title: 'Batch progress',
    total: 2,
    onCancel: onCancel ?? () {},
  );

  testWidgets('Back uses Cancel once and repeated completion preserves Songs', (
    tester,
  ) async {
    await mount(tester);
    var cancellations = 0;
    late VoidCallback dismiss;
    dismiss = show(
      onCancel: () {
        cancellations++;
        dismiss();
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(cancellations, 1);
    expect(find.text('Songs'), findsOneWidget);
    dismiss();
    BatchProgressDialog.dismiss(pageContext);
    await tester.pumpAndSettle();
    expect(find.text('Songs'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completion removes only its route when Settings covers it', (
    tester,
  ) async {
    await mount(tester);
    var cancellations = 0;
    final dismiss = show(onCancel: () => cancellations++);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    navigator.currentState!.push<void>(
      MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Settings'))),
    );
    await tester.pumpAndSettle();
    dismiss();
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(cancellations, 0);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Songs'), findsOneWidget);
    expect(find.byType(BatchProgressDialog), findsNothing);
  });

  testWidgets('completion before first frame still removes only the dialog', (
    tester,
  ) async {
    await mount(tester);
    final dismiss = show();
    dismiss();
    await tester.pumpAndSettle();
    expect(find.text('Songs'), findsOneWidget);
    expect(find.byType(BatchProgressDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('external removal cancels and later completion is harmless', (
    tester,
  ) async {
    await mount(tester);
    var cancellations = 0;
    final dismiss = show(onCancel: () => cancellations++);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final route = ModalRoute.of(
      tester.element(find.byType(BatchProgressDialog)),
    )!;
    navigator.currentState!.removeRoute(route);
    await tester.pumpAndSettle();
    expect(cancellations, 1);
    navigator.currentState!.push<void>(
      MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Settings'))),
    );
    await tester.pumpAndSettle();
    dismiss();
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('old completion cannot dismiss a newer progress dialog', (
    tester,
  ) async {
    await mount(tester);
    final dismissOld = show();
    await tester.pump();
    dismissOld();
    await tester.pumpAndSettle();
    final dismissNew = show();
    await tester.pump();
    dismissOld();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(BatchProgressDialog), findsOneWidget);
    dismissNew();
    await tester.pumpAndSettle();
    expect(find.text('Songs'), findsOneWidget);
  });
}
