import 'package:flutter/material.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';

/// Keeps selection alive when the actions are tucked away. One downward
/// gesture collapses the actions; only a new gesture on the compact header
/// dismisses selection. Action scrolling never hides the header.
class AppSelectionPanelDrag extends StatefulWidget {
  const AppSelectionPanelDrag({
    super.key,
    required this.onClose,
    required this.header,
    required this.bottomPadding,
    required this.children,
    required this.surfaceBuilder,
  });

  final VoidCallback onClose;
  final Widget header;
  final double bottomPadding;
  final List<Widget> children;
  final Widget Function(Widget) surfaceBuilder;

  @override
  State<AppSelectionPanelDrag> createState() => _SelectionPanelDragState();
}

class _SelectionPanelDragState extends State<AppSelectionPanelDrag>
    with TickerProviderStateMixin {
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );
  late final _SelectionPanelScrollController _scroll =
      _SelectionPanelScrollController(_drag, _settle);
  late final AnimationController _expansion = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 220),
  );
  final _actionsKey = GlobalKey();
  bool _expanded = true;
  bool? _dragFromExpanded;
  double _pull = 0;
  double _actionHeight = 1;
  bool _closing = false;

  double _drag(double delta) {
    if (_closing) return 0;
    if (_dragFromExpanded == null) {
      if (_expanded && _expansion.value == 1 && delta <= 0) return delta;
      _dragFromExpanded = _expanded;
      _actionHeight = (_actionsKey.currentContext?.size?.height ?? 1).clamp(
        1.0,
        double.infinity,
      );
      _pull = _expanded
          ? (1 - _expansion.value) * _actionHeight
          : _offset.value - _expansion.value * _actionHeight;
    }
    _offset.stop();
    _expansion.stop();
    if (_dragFromExpanded!) {
      final previous = _pull;
      _pull = (_pull + delta).clamp(0.0, _actionHeight);
      _expansion.value = 1 - _pull / _actionHeight;
      // A single pull can reach the compact state, but cannot cancel it.
      return delta < 0 ? delta - (_pull - previous) : 0;
    }
    _pull = (_pull + delta).clamp(-_actionHeight, double.infinity);
    _expansion.value = (-_pull / _actionHeight).clamp(0.0, 1.0);
    _offset.value = _pull.clamp(0.0, double.infinity);
    return 0;
  }

  bool _settle(double velocity) {
    if (_closing) return true;
    final fromExpanded = _dragFromExpanded;
    if (fromExpanded == null) return false;
    _dragFromExpanded = null;
    final threshold = (_actionHeight * 0.25).clamp(64.0, 120.0);
    if (fromExpanded) {
      final collapse =
          velocity > 700 || (velocity >= -700 && _pull >= threshold);
      _setExpanded(!collapse);
      return true;
    }
    if (_pull < 0) {
      final expand =
          velocity < -700 || (velocity <= 700 && -_pull >= threshold);
      _setExpanded(expand);
      return true;
    }
    final height = context.size?.height ?? 0;
    _closing =
        velocity > 700 ||
        (velocity >= -700 && _offset.value >= (height * 0.25).clamp(64, 120));
    _animateToRest(_closing ? height : 0);
    return true;
  }

  void _setExpanded(bool expanded) {
    setState(() => _expanded = expanded);
    if (!expanded && _scroll.hasClients) _scroll.jumpTo(0);
    _expansion.animateTo(
      expanded ? 1 : 0,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
    _animateToRest(0);
  }

  void _toggleExpanded() {
    if (_closing) return;
    _dragFromExpanded = null;
    _setExpanded(!_expanded);
  }

  void _cancelDrag() {
    final fromExpanded = _dragFromExpanded;
    _dragFromExpanded = null;
    if (fromExpanded != null) _setExpanded(fromExpanded);
  }

  Future<void> _animateToRest(double target) async {
    try {
      await _offset
          .animateTo(
            target,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          )
          .orCancel;
      if (mounted && _closing) widget.onClose();
    } on TickerCanceled {
      // Another drag or route disposal can interrupt the settling animation.
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _offset.dispose();
    _expansion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _offset,
    builder: (_, child) =>
        Transform.translate(offset: Offset(0, _offset.value), child: child),
    child: widget.surfaceBuilder(
      ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              widget.bottomPadding > 0 ? 8 : 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) => _drag(details.delta.dy),
                  onVerticalDragEnd: (details) =>
                      _settle(details.primaryVelocity ?? 0),
                  onVerticalDragCancel: _cancelDrag,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        container: true,
                        button: true,
                        expanded: _expanded,
                        label: _expanded
                            ? MaterialLocalizations.of(
                                context,
                              ).expandedIconTapHint
                            : MaterialLocalizations.of(
                                context,
                              ).collapsedIconTapHint,
                        onTap: _toggleExpanded,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          excludeFromSemantics: true,
                          onTap: _toggleExpanded,
                          child: const SizedBox(
                            height: 32,
                            child: AppSheetHandle(margin: EdgeInsets.zero),
                          ),
                        ),
                      ),
                      widget.header,
                    ],
                  ),
                ),
                Flexible(
                  child: ExcludeSemantics(
                    excluding: !_expanded,
                    child: IgnorePointer(
                      ignoring: !_expanded,
                      child: SizeTransition(
                        sizeFactor: _expansion,
                        alignment: Alignment.topCenter,
                        child: SingleChildScrollView(
                          key: _actionsKey,
                          controller: _scroll,
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: ClampingScrollPhysics(),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 12),
                              ...widget.children,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _SelectionPanelScrollController extends ScrollController {
  _SelectionPanelScrollController(this.dragPanel, this.settlePanel);

  final double Function(double) dragPanel;
  final bool Function(double) settlePanel;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _SelectionPanelScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    dragPanel: dragPanel,
    settlePanel: settlePanel,
  );
}

class _SelectionPanelScrollPosition extends ScrollPositionWithSingleContext {
  _SelectionPanelScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required this.dragPanel,
    required this.settlePanel,
  });

  final double Function(double) dragPanel;
  final bool Function(double) settlePanel;

  @override
  void applyUserOffset(double delta) {
    // Scroll back to the top before handing any remaining drag to the panel.
    if (delta > 0 && pixels > minScrollExtent) {
      final scrollDelta = delta.clamp(0.0, pixels - minScrollExtent);
      super.applyUserOffset(scrollDelta);
      delta -= scrollDelta;
    }
    final remaining = dragPanel(delta);
    if (remaining != 0) super.applyUserOffset(remaining);
  }

  @override
  void goBallistic(double velocity) {
    final movingPanel = settlePanel(-velocity);
    super.goBallistic(movingPanel ? 0 : velocity);
  }
}
