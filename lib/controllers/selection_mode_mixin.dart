import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mornye/widgets/track_lists/list_selection.dart';
import 'package:mornye/widgets/selection_bottom_bar.dart';

/// Shared multi-select state for list screens: enter/exit selection mode,
/// toggle individual items, select all, and prune ids that fell out of the
/// current item list. Mix into a `State<T>` alongside the screen's own
/// per-item lookups. Used by the album, artist, playlist, downloaded album,
/// local album and library tracks folder screens; queue_tab keeps its own
/// selection state.
///
/// which drive the same selection mode.
mixin SelectionModeMixin<T extends StatefulWidget> on State<T> {
  bool isSelectionMode = false;
  final Set<String> selectedIds = {};

  /// A right-click selected an item for its menu only, so the selection bar
  /// stays hidden until the menu and its chosen action have run.
  bool contextMenuSelection = false;

  /// Whether the screen shows its selection bar.
  bool get showsSelectionBar => isSelectionMode && !contextMenuSelection;

  /// Shift.
  String? selectionAnchorId;

  void enterSelectionMode(String itemId) {
    HapticFeedback.mediumImpact();
    setState(() {
      isSelectionMode = true;
      selectedIds.add(itemId);
      selectionAnchorId = itemId;
    });
  }

  void exitSelectionMode() {
    setState(() {
      isSelectionMode = false;
      selectedIds.clear();
      selectionAnchorId = null;
    });
  }

  /// visible items in display order, for Shift ranges.
  void applySelectionClick(
    String itemId,
    RowClick kind,
    List<String> orderedIds,
  ) {
    setState(() {
      selectionAnchorId = applySelectionClickTo(
        selectedIds,
        target: itemId,
        kind: kind,
        orderedIds: orderedIds,
        anchor: selectionAnchorId,
      );
      isSelectionMode = selectedIds.isNotEmpty;
    });
  }

  /// row was chosen. A right-click outside the selection selects only that
  /// item, so the menu acts on the item it was opened on. That selection is
  /// for the menu: the bar stays hidden under it, and the selection ends if
  /// the menu closes without a choice.
  Future<void> showSelectionMenu(
    String itemId,
    Future<bool> Function() show,
  ) async {
    final forMenu = !selectedIds.contains(itemId);
    if (forMenu) {
      contextMenuSelection = true;
      applySelectionClick(itemId, RowClick.replace, const []);
    }
    final chosen = await show();
    if (!forMenu || !mounted) return;
    // An action that kept the selection shows the bar again.
    setState(() => contextMenuSelection = false);
    if (!chosen) exitSelectionMode();
  }

  void toggleSelection(String itemId) {
    setState(() {
      if (selectedIds.contains(itemId)) {
        selectedIds.remove(itemId);
        if (selectedIds.isEmpty) {
          isSelectionMode = false;
        }
      } else {
        selectedIds.add(itemId);
      }
    });
  }

  /// Cmd/Ctrl+A.
  void selectAll(Iterable<String> ids) {
    setState(() {
      selectedIds.addAll(ids);
      if (selectedIds.isNotEmpty) isSelectionMode = true;
    });
  }

  /// The selection bar over [ids], every selectable item in display order.
  /// Toggling with everything selected calls [onDeselectAll], which exits
  /// selection mode by default.
  Widget buildSelectionBar({
    required List<String> ids,
    required double bottomPadding,
    required List<Widget> children,
    VoidCallback? onDeselectAll,
    String? allSelectedLabel,
    String? tapToSelectLabel,
  }) {
    final allSelected = ids.isNotEmpty && selectedIds.length == ids.length;
    return SelectionBottomBar(
      selectedCount: selectedIds.length,
      allSelected: allSelected,
      onClose: exitSelectionMode,
      onToggleSelectAll: allSelected
          ? onDeselectAll ?? exitSelectionMode
          : () => selectAll(ids),
      bottomPadding: bottomPadding,
      allSelectedLabel: allSelectedLabel,
      tapToSelectLabel: tapToSelectLabel,
      children: children,
    );
  }

  /// Drops ids no longer present in [validIds]; call from build() with the
  /// current item ids. Exits selection mode next frame if that empties it.
  void pruneSelection(Set<String> validIds) {
    selectedIds.removeWhere((id) => !validIds.contains(id));
    if (selectedIds.isEmpty && isSelectionMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => isSelectionMode = false);
      });
    }
  }
}
