import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

bool get selectionModifierPressed {
  final keyboard = HardwareKeyboard.instance;
  return keyboard.isControlPressed;
}

/// The selection change for a click made with the modifiers held right now.
RowClick selectionClickKind() {
  if (HardwareKeyboard.instance.isShiftPressed) return RowClick.extend;
  if (selectionModifierPressed) return RowClick.toggle;
  return RowClick.replace;
}

/// Whether [event] is Shift+F10 or the Menu key, which open the context menu
/// of the focused item.
bool isContextMenuKey(KeyEvent event) {
  if (event is! KeyDownEvent) return false;
  final key = event.logicalKey;
  if (key == LogicalKeyboardKey.contextMenu) return true;
  return key == LogicalKeyboardKey.f10 &&
      HardwareKeyboard.instance.isShiftPressed;
}

/// Detects double clicks on rows that rebuild between the two clicks, which
/// would reset a per-widget recognizer.
abstract final class RowDoubleClick {
  static const timeout = Duration(milliseconds: 500);

  static Object? _lastTarget;
  static DateTime? _lastAt;

  /// Records a plain click on [target] and returns true when it completes a
  /// double click on the same target.
  static bool register(Object target) {
    final now = DateTime.now();
    final last = _lastAt;
    final isDouble =
        _lastTarget == target &&
        last != null &&
        now.difference(last) <= timeout;
    _lastTarget = isDouble ? null : target;
    _lastAt = isDouble ? null : now;
    return isDouble;
  }

  /// Forgets the last click, so the next one starts a new sequence.
  static void reset() {
    _lastTarget = null;
    _lastAt = null;
  }
}

/// An item that can open its context menu from the keyboard.
abstract interface class ContextMenuTarget {
  bool get mounted;

  void openContextMenuFromKeyboard();
}

///
/// A click anywhere inside takes keyboard focus for the list (the scope node
/// itself, so Space still toggles playback). While it has focus:
/// Cmd/Ctrl+A runs [onSelectAll], Escape runs [onClearSelection], Delete or
/// Backspace runs [onDelete], Enter runs [onActivate], and Shift+F10 or the
/// Menu key opens the context menu of the item clicked last. Text fields keep
/// their own keys. Phones and tablets get [child] unchanged.
class ListScope extends StatefulWidget {
  const ListScope({
    super.key,
    required this.child,
    this.onSelectAll,
    this.onClearSelection,
    this.onDelete,
    this.onActivate,
  });

  final Widget child;
  final VoidCallback? onSelectAll;

  /// Null while nothing is selected, so Escape falls through and closes the
  /// page.
  final VoidCallback? onClearSelection;

  /// Removes the selection; null where the list has no removal.
  final VoidCallback? onDelete;

  /// Plays or opens the selection anchor.
  final VoidCallback? onActivate;

  @override
  State<ListScope> createState() => _ListScopeState();
}

class _ListScopeState extends State<ListScope> {
  final _node = FocusScopeNode(debugLabel: 'ListScope');

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
