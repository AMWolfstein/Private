import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/screens/library/shared/selection_mode_mixin.dart';

class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SelectionModeMixin<_Host> {
  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets('long press selects one item and toggling it off ends the mode', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _Host()));
    final state = tester.state<_HostState>(find.byType(_Host));

    state.enterSelectionMode('a');
    expect(state.isSelectionMode, isTrue);
    expect(state.selectedIds, {'a'});

    state.toggleSelection('b');
    expect(state.selectedIds, {'a', 'b'});

    state.toggleSelection('a');
    state.toggleSelection('b');
    expect(state.selectedIds, isEmpty);
    expect(state.isSelectionMode, isFalse);
  });

  testWidgets('select all adds every id and exit clears the selection', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _Host()));
    final state = tester.state<_HostState>(find.byType(_Host));
    state.enterSelectionMode('a');
    state.selectAll(['b', 'c']);
    expect(state.selectedIds, {'a', 'b', 'c'});

    state.exitSelectionMode();
    expect(state.isSelectionMode, isFalse);
    expect(state.selectedIds, isEmpty);
  });

  testWidgets('pruning drops ids that are no longer listed', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Host()));
    final state = tester.state<_HostState>(find.byType(_Host));
    state.enterSelectionMode('a');
    state.selectAll(['b']);

    state.pruneSelection({'b'});
    expect(state.selectedIds, {'b'});
    expect(state.isSelectionMode, isTrue);
  });

  testWidgets('pruning away every selected id leaves selection mode', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _Host()));
    final state = tester.state<_HostState>(find.byType(_Host));
    state.enterSelectionMode('gone');

    state.pruneSelection({'other'});
    await tester.pump();
    expect(state.selectedIds, isEmpty);
    expect(state.isSelectionMode, isFalse);
  });
}
