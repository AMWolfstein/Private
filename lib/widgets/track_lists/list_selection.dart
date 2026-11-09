import 'package:mornye/utils/ordered_range_selection.dart';

enum RowClick {
  /// A plain click: the item becomes the whole selection.
  replace,

  toggle,

  /// Shift-click: selects the range from the anchor to the item.
  extend,
}

/// the new range anchor. [orderedIds] lists the visible items in display
/// order. A Shift range replaces the selection and keeps [anchor], as in
/// Finder and Explorer.
T? applySelectionClickTo<T>(
  Set<T> selected, {
  required T target,
  required RowClick kind,
  required List<T> orderedIds,
  required T? anchor,
}) {
  switch (kind) {
    case RowClick.replace:
      selected
        ..clear()
        ..add(target);
      return target;
    case RowClick.toggle:
      return toggleOrderedSelection(selected: selected, target: target);
    case RowClick.extend:
      selected.clear();
      addOrderedSelectionRange(
        selected: selected,
        visibleItems: orderedIds,
        target: target,
        anchor: anchor,
      );
      return anchor ?? target;
  }
}
