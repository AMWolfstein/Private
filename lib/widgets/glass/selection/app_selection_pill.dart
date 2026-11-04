import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g1455/g1455.dart'
    show GlassDropMotion, GlassDropStretchDriver, GlassSurface;
import 'package:sistrum/widgets/glass/thumb/app_glass_surface.dart'
    show kAppLiquidGlassFinish;
import 'package:sistrum/widgets/glass/selection/app_selection_foreground.dart';
import 'package:sistrum/widgets/glass/selection/app_selection_shared.dart';

part 'app_selection_pill_motion.dart';

Future<ui.FragmentProgram>? _selectionMaskProgram;
ui.FragmentProgram? _loadedSelectionMaskProgram;
const _heldWidthGrowth = 0.28;
const _heldHeightGrowth = 0.24;

// g1455's GlassTabBar motion. The press lifts on a spring that rises a few
// percent past held and settles; the pill slides between items on a second
// one, keeping the finger's speed into the settle.
const _liftSpring = SpringDescription(mass: 1, stiffness: 520, damping: 34);
const _slideSpring = SpringDescription(mass: 1, stiffness: 380, damping: 36);
// Ends a spring where the motion is under a device pixel.
const _springTolerance = Tolerance(distance: 0.004, velocity: 0.05);

/// Selection with a Tinted Lite glass pill over the fixed-size foreground
/// while held. It frosts the bar's backdrop behind the icons, rendered only
/// while a press is in progress.
class AppSelectionPill extends ConsumerStatefulWidget {
  const AppSelectionPill({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    required this.itemBuilder,
    this.padding = const EdgeInsets.all(4),
    this.glassInteraction = false,
    this.contrastBlocked,
    this.selectionColor,
    this.maskItemForeground = true,
    this.interactionBuilder,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final Widget Function(BuildContext context, int index, bool selected)
  itemBuilder;
  final EdgeInsets padding;

  /// Whether a press shows the held glass pill (touch-only, never at rest).
  final bool glassInteraction;

  /// The parent's glass contrast policy, including an explicit user override.
  /// Standalone controls respect the system contrast request by default.
  final bool? contrastBlocked;

  /// Recolors the foreground under the moving pill instead of switching an
  /// entire item at a tab boundary. Builders receive `selected: false` in this
  /// mode so the unmasked foreground retains its normal color.
  final Color? selectionColor;
  final bool maskItemForeground;

  /// Lets the bar animate its glass behind the fixed-size foreground using the
  /// same press/release animation as the held pill.
  final Widget Function(BuildContext context, double progress, Widget child)?
  interactionBuilder;

  @override
  ConsumerState<AppSelectionPill> createState() => _AppSelectionPillState();
}

class _AppSelectionPillState extends ConsumerState<AppSelectionPill>
    with TickerProviderStateMixin {
  int? _dragIndex;
  bool _dragCancelled = false;
  bool _pressed = false;
  int? _pressedIndex;
  double? _dragAlignment;
  int? _activePointer;
  final _foregroundKey = GlobalKey();

  /// 0 at rest, 1 held, and past 1 for a moment: it is a spring.
  late final AnimationController _lift;

  /// Where the pill is, in item units (0 is the first item).
  late final AnimationController _at;

  /// The item [_at] is heading for when it is not under the finger.
  double? _slideTarget;

  /// The width of one item, for the stretch's position in pixels.
  double _pitch = 1;

  late final GlassDropStretchDriver _stretch;
  ui.FragmentProgram? _maskProgram;
  Widget? _items;
  int? _itemsSelected;

  @override
  void initState() {
    super.initState();
    _lift = AnimationController.unbounded(vsync: this)
      ..addListener(() => setState(() {}));
    _at = AnimationController.unbounded(
      vsync: this,
      value: widget.selectedIndex.toDouble(),
    )..addListener(_moved);
    _slideTarget = widget.selectedIndex.toDouble();
    _stretch = GlassDropStretchDriver(
      vsync: this,
      position: () => _at.value * _pitch,
    )..addListener(() => setState(() {}));
    if (widget.selectionColor != null) unawaited(_loadMaskProgram());
  }

  @override
  void dispose() {
    _stretch.dispose();
    _at.dispose();
    _lift.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _items = null;
    _stretch.motion = GlassDropMotion.resolve(context, null);
  }

  /// The pill moved: repaint, and deform it only while there is a drop.
  void _moved() {
    setState(() {});
    if (_pressed || _lift.value > 0) _stretch.wake();
  }

  /// Lifts or settles the press on g1455's lift spring, landing exactly on
  /// [target] once inside it.
  void _liftTo(double target) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _lift.value = target;
      return;
    }
    _lift
        .animateWith(
          SpringSimulation(
            _liftSpring,
            _lift.value,
            target,
            _lift.velocity,
            tolerance: _springTolerance,
          ),
        )
        .then((_) => _lift.value = target, onError: (_) {});
  }

  /// Slides the pill to the item it should rest on (a drag places it
  /// directly instead), carrying [velocity] in items per second.
  void _follow({double velocity = 0}) {
    if (_dragAlignment != null) return;
    final target = (_dragIndex ?? _pressedIndex ?? widget.selectedIndex)
        .toDouble();
    if (target == _slideTarget && (_at.isAnimating || _at.value == target)) {
      return;
    }
    _slideTarget = target;
    if (MediaQuery.disableAnimationsOf(context)) {
      _at.value = target;
      return;
    }
    _at
        .animateWith(
          SpringSimulation(
            _slideSpring,
            _at.value,
            target,
            velocity,
            tolerance: _springTolerance,
          ),
        )
        .then((_) => _at.value = target, onError: (_) {});
  }

  @override
  void didUpdateWidget(AppSelectionPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    _items = null;
    if (oldWidget.selectionColor == null && widget.selectionColor != null) {
      unawaited(_loadMaskProgram());
    }
    _stretch.motion = GlassDropMotion.resolve(context, null);
    if (oldWidget.labels.length != widget.labels.length ||
        oldWidget.selectedIndex != widget.selectedIndex) {
      _dragIndex = null;
      _dragAlignment = null;
      _pressedIndex = null;
      _follow();
    }
  }

  /// The pill's alignment for [_at], in [AlignmentDirectional] terms.
  double _alignmentOf(int count) =>
      count == 1 ? 0 : -1 + 2 * _at.value / (count - 1);

  void _rebuild(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    final count = widget.labels.length;
    if (count == 0) return const SizedBox.shrink();
    final selected = _dragIndex ?? _pressedIndex ?? widget.selectedIndex;
    final scheme = Theme.of(context).colorScheme;
    final glassEnabled =
        widget.glassInteraction &&
        !MediaQuery.disableAnimationsOf(context) &&
        !(widget.contrastBlocked ?? MediaQuery.highContrastOf(context));
    final pressProgress = glassEnabled ? _lift.value : 0.0;
    final restingOpacity = (1 - pressProgress).clamp(0.0, 1.0);
    // The held drop stretches as it launches and squashes as it brakes
    // (g1455's GlassDropStretch), only as far as it is lifted.
    final stretch = _stretch.value * pressProgress.clamp(0.0, 1.0);
    final content = Listener(
      // An accepted drag can end with a PointerCancelEvent. Do not navigate
      // when the OS interrupts the gesture (e.g. opening system controls).
      onPointerDown: (event) {
        if (_activePointer != null) return;
        _activePointer = event.pointer;
        _dragCancelled = false;
        if (!glassEnabled || _pressed) return;
        final box = context.findRenderObject()! as RenderBox;
        final width = box.size.width - widget.padding.horizontal;
        if (width <= 0) return;
        final visual =
            ((event.localPosition.dx - widget.padding.left) / width * count)
                .floor()
                .clamp(0, count - 1);
        setState(() {
          _pressed = true;
          _pressedIndex = Directionality.of(context) == TextDirection.rtl
              ? count - visual - 1
              : visual;
        });
        _liftTo(1);
        _follow();
      },
      onPointerUp: (event) {
        if (event.pointer != _activePointer) return;
        _activePointer = null;
        _liftTo(0);
        setState(() {
          _pressed = false;
          _pressedIndex = null;
          _dragAlignment = null;
        });
        _follow(velocity: _at.velocity);
      },
      onPointerCancel: (event) {
        if (event.pointer != _activePointer) return;
        _activePointer = null;
        _liftTo(0);
        setState(() {
          _dragCancelled = true;
          _pressed = false;
          _pressedIndex = null;
          _dragAlignment = null;
        });
        _follow();
      },
      child: Padding(
        padding: widget.padding,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _pitch = constraints.maxWidth / count;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (event) =>
                  _preview(event.localPosition.dx, constraints.maxWidth),
              onHorizontalDragUpdate: (event) =>
                  _preview(event.localPosition.dx, constraints.maxWidth),
              onHorizontalDragEnd: (details) {
                final index = _dragIndex;
                setState(() {
                  _dragIndex = null;
                  _dragAlignment = null;
                });
                // The pill keeps the finger's speed into the settle, in items
                // per second; under rtl a fling to the left heads forward.
                final rtl = Directionality.of(context) == TextDirection.rtl;
                final velocity =
                    details.velocity.pixelsPerSecond.dx /
                    _pitch *
                    (rtl ? -1 : 1);
                if (index != null && !_dragCancelled) {
                  widget.onChanged(index);
                }
                _follow(velocity: velocity);
              },
              onHorizontalDragCancel: () {
                setState(() {
                  _dragIndex = null;
                  _dragAlignment = null;
                });
                _follow();
              },
              child: Stack(
                fit: StackFit.passthrough,
                clipBehavior: Clip.none,
                children: [
                  if (selected >= 0 && selected < count)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Align(
                          alignment: AlignmentDirectional(
                            _alignmentOf(count),
                            0,
                          ),
                          child: FractionallySizedBox(
                            widthFactor: 1 / count,
                            heightFactor: 1,
                            // Share the held glass outline while fading into it.
                            // A fixed resting pill leaves a second capsule
                            // inside the held glass, especially during release.
                            child: Transform.scale(
                              scaleX: 1 + _heldWidthGrowth * pressProgress,
                              scaleY: 1 + _heldHeightGrowth * pressProgress,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: scheme.onSurface.withValues(
                                    alpha:
                                        restingOpacity *
                                        // A soft light highlight, as in
                                        // Apple Music's floating tab bar.
                                        (scheme.brightness == Brightness.dark
                                            ? 0.12
                                            : 0.04),
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    kAppSelectionPillRadius,
                                  ),
                                  border: Border.all(
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.05 * restingOpacity,
                                    ),
                                    width: 0.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.08 * restingOpacity,
                                      ),
                                      blurRadius: 1,
                                      offset: const Offset(0, 0.5),
                                      // Edge only: under the translucent
                                      // fill it would darken the pill.
                                      blurStyle: BlurStyle.outer,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  _foreground(
                    selected,
                    count,
                    pressProgress,
                    stretch,
                    _buildItems(selected),
                  ),
                  // The held glass samples the foreground as well as the page,
                  // so the icons read through it.
                  if (glassEnabled &&
                      pressProgress > 0 &&
                      selected >= 0 &&
                      selected < count)
                    _heldGlass(selected, count, pressProgress, stretch),
                ],
              ),
            );
          },
        ),
      ),
    );
    return widget.interactionBuilder?.call(context, pressProgress, content) ??
        content;
  }
}
