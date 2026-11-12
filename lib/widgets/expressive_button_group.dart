import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:mornye/theme/app_motion.dart';

/// A row of header actions laid out as a Material 3 Expressive button group.
///
/// [flexible] actions share the free width; the others keep a [slotWidth]
/// box. Pressing an action widens it while its neighbours give way. Without
/// expressive motion the row keeps the centred, content-sized layout with
/// [Flexible] actions that it replaces.
class ExpressiveButtonGroup extends StatefulWidget {
  const ExpressiveButtonGroup({
    super.key,
    required this.children,
    this.flexible = const {},
    this.spacing = 12,
    this.slotWidth = 48,
  });

  final List<Widget> children;

  /// Indices of [children] that fill the remaining width.
  final Set<int> flexible;
  final double spacing;
  final double slotWidth;

  @override
  State<ExpressiveButtonGroup> createState() => _ExpressiveButtonGroupState();
}

/// Width an [ExpressiveButtonGroup] gives a fixed action, so an icon button
/// can stretch its container along with the squish.
class ExpressiveButtonGroupSlot extends InheritedWidget {
  const ExpressiveButtonGroupSlot({
    super.key,
    required this.width,
    required super.child,
  });

  final double width;

  static double? widthOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ExpressiveButtonGroupSlot>()
      ?.width;

  @override
  bool updateShouldNotify(ExpressiveButtonGroupSlot oldWidget) =>
      width != oldWidget.width;
}

/// Tracks which slot of an expressive group is pressed, so it can widen by
/// [squishRatio] on [pressSpring] while its neighbours give way.
mixin ExpressivePressSquish<T extends StatefulWidget> on State<T> {
  static final _pressSpring = SpringCurve(M3EMotion.expressiveSpatialPress);

  double get squishRatio => 0.15;
  SpringCurve get pressSpring => _pressSpring;
  int? pressedIndex;

  Widget pressSlot(int index, Widget child) => Listener(
    onPointerDown: (_) => _press(index),
    onPointerUp: (_) => _press(null),
    onPointerCancel: (_) => _press(null),
    child: child,
  );

  void _press(int? index) {
    if (pressedIndex != index) setState(() => pressedIndex = index);
  }
}

class _ExpressiveButtonGroupState extends State<ExpressiveButtonGroup>
    with ExpressivePressSquish {
  @override
  Widget build(BuildContext context) {
    final children = widget.children;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: widget.spacing),
          widget.flexible.contains(i)
              ? Flexible(child: children[i])
              : children[i],
        ],
      ],
    );
  }
}
