import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/primitives/app_content_card.dart';

Future<void> _pump(WidgetTester tester, Widget card) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.build(Brightness.light),
    home: Scaffold(body: Center(child: card)),
  ),
);

Material _surface(WidgetTester tester) => tester.widget<Material>(
  find.descendant(
    of: find.byType(AppContentCard),
    matching: find.byType(Material),
  ),
);

void main() {
  testWidgets('wraps its child in a rounded control surface', (tester) async {
    await _pump(tester, const AppContentCard(child: Text('Row')));

    expect(find.text('Row'), findsOneWidget);
    final surface = _surface(tester);
    expect(surface.borderRadius, BorderRadius.circular(28));
    expect(surface.clipBehavior, Clip.antiAlias);
  });

  testWidgets('uses the theme control fill unless the colour is preserved', (
    tester,
  ) async {
    late Color expectedFill;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Builder(
          builder: (context) {
            expectedFill = AppTheme.controlFill(context);
            return const Scaffold(
              body: AppContentCard(color: Colors.red, child: SizedBox()),
            );
          },
        ),
      ),
    );
    expect(_surface(tester).color, expectedFill);
  });

  testWidgets('keeps an explicit colour when preserveColor is set', (
    tester,
  ) async {
    await _pump(
      tester,
      const AppContentCard(
        color: Colors.red,
        preserveColor: true,
        child: SizedBox(),
      ),
    );
    expect(_surface(tester).color, Colors.red);
  });

  testWidgets('scopes divider colour to the card content', (tester) async {
    await _pump(
      tester,
      Builder(
        builder: (context) => const AppContentCard(child: _DividerProbe()),
      ),
    );
    final probe = tester.state<_DividerProbeState>(find.byType(_DividerProbe));
    expect(probe.dividerColor, AppTheme.metadataDividerColor(probe.context));
  });
}

class _DividerProbe extends StatefulWidget {
  const _DividerProbe();

  @override
  State<_DividerProbe> createState() => _DividerProbeState();
}

class _DividerProbeState extends State<_DividerProbe> {
  Color? dividerColor;

  @override
  Widget build(BuildContext context) {
    dividerColor = DividerTheme.of(context).color;
    return const SizedBox();
  }
}
