import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:sistrum/core/theme/app_glass_levels.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/widgets/glass/thumb/app_liquid_backdrop.dart';
import 'package:sistrum/widgets/glass/selection/app_selection_foreground.dart';
import 'package:sistrum/widgets/glass/selection/app_selection_shared.dart';

part 'app_selection_pill_motion.dart';

Future<ui.FragmentProgram>? _selectionMaskProgram;
ui.FragmentProgram? _loadedSelectionMaskProgram;
const _heldWidthGrowth = 0.28;
const _heldHeightGrowth = 0.24;
// The package nav bar's tab-scale squash/stretch (deformation capped at 12%).
const _dragMotion = LiquidGlassLensMotionSpec(maxDeformation: 0.12);

/// Selection with a transient lens over the fixed-size foreground while held.
/// It refracts both the bar's backdrop and its icons, rendered only once.
class AppSelectionPill extends ConsumerStatefulWidget {
  const AppSelectionPill({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    required this.itemBuilder,
    this.padding = const EdgeInsets.all(4),
    this.liquidInteraction = false,
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
  final bool liquidInteraction;

  /// The parent's glass contrast policy, including an explicit user override.
  /// Standalone controls respect the system contrast request by default.
  final bool? contrastBlocked;

  /// Recolors the foreground under the moving pill instead of switching an
  /// entire item at a tab boundary. Builders receive `selected: false` in this
  /// mode so the unmasked foreground retains its normal color.
  final Color? selectionColor;
  final bool maskItemForeground;

  /// Lets the bar animate its glass behind the fixed-size foreground using the
  /// same press/release animation as the selection lens.
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
  late final AnimationController _pressController;
  late final CurvedAnimation _pressAnimation;
  ui.FragmentProgram? _maskProgram;
  Widget? _items;
  int? _itemsSelected;

  /// Squash/stretch of the held pill while it is dragged between tabs.
  final _motion = LiquidGlassLensMotion(spec: _dragMotion);
  Ticker? _motionTicker;
  Duration? _motionLast;
  double _laneWidth = 0;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _pressAnimation = CurvedAnimation(
      parent: _pressController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    )..addListener(() => setState(() {}));
    if (widget.selectionColor != null) unawaited(_loadMaskProgram());
  }

  @override
  void dispose() {
    _motionTicker?.dispose();
    _pressAnimation.dispose();
    _pressController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _items = null;
  }

  @override
  void didUpdateWidget(AppSelectionPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    _items = null;
    if (oldWidget.selectionColor == null && widget.selectionColor != null) {
      unawaited(_loadMaskProgram());
    }
    if (oldWidget.labels.length != widget.labels.length ||
        oldWidget.selectedIndex != widget.selectedIndex) {
      _dragIndex = null;
      _dragAlignment = null;
      _pressedIndex = null;
    }
  }

  void _rebuild(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    final count = widget.labels.length;
    if (count == 0) return const SizedBox.shrink();
    final selected = _dragIndex ?? _pressedIndex ?? widget.selectedIndex;
    final scheme = Theme.of(context).colorScheme;
    final outlines = ref.watch(appGlassOutlinesProvider);
    final lensEnabled =
        widget.liquidInteraction &&
        ref.watch(appShaderFiltersSupportedProvider) &&
        !MediaQuery.disableAnimationsOf(context) &&
        !(widget.contrastBlocked ?? MediaQuery.highContrastOf(context));
    final pressProgress = lensEnabled ? _pressAnimation.value : 0.0;
    // Only the held glass deforms; the resting pill keeps its shape.
    final deviation = lensEnabled ? _motion.deviation * pressProgress : 0.0;
    final restingOpacity = 1 - pressProgress;
    final content = Listener(
      // An accepted drag can end with a PointerCancelEvent. Do not navigate
      // when the OS interrupts the gesture (e.g. opening system controls).
      onPointerDown: (event) {
        if (_activePointer != null) return;
        _activePointer = event.pointer;
        _dragCancelled = false;
        if (!lensEnabled || _pressed) return;
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
        _pressController.forward();
      },
      onPointerUp: (event) {
        if (event.pointer != _activePointer) return;
        _activePointer = null;
        _stopMotion();
        _pressController.reverse();
        setState(() {
          _pressed = false;
          _pressedIndex = null;
          _dragAlignment = null;
        });
      },
      onPointerCancel: (event) {
        if (event.pointer != _activePointer) return;
        _activePointer = null;
        _stopMotion();
        _pressController.reverse();
        setState(() {
          _dragCancelled = true;
          _pressed = false;
          _pressedIndex = null;
          _dragAlignment = null;
        });
      },
      child: Padding(
        padding: widget.padding,
        child: LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (event) =>
                _preview(event.localPosition.dx, constraints.maxWidth),
            onHorizontalDragUpdate: (event) =>
                _preview(event.localPosition.dx, constraints.maxWidth),
            onHorizontalDragEnd: (_) {
              final index = _dragIndex;
              setState(() {
                _dragIndex = null;
                _dragAlignment = null;
              });
              if (index != null && !_dragCancelled) widget.onChanged(index);
            },
            onHorizontalDragCancel: () => setState(() {
              _dragIndex = null;
              _dragAlignment = null;
            }),
            child: Stack(
              fit: StackFit.passthrough,
              clipBehavior: Clip.none,
              children: [
                if (selected >= 0 && selected < count)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedAlign(
                        duration:
                            _dragAlignment != null ||
                                MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: AlignmentDirectional(
                          _dragAlignment ??
                              (count == 1
                                  ? 0
                                  : -1 + 2 * selected / (count - 1)),
                          0,
                        ),
                        child: FractionallySizedBox(
                          widthFactor: 1 / count,
                          heightFactor: 1,
                          // Share the lens outline while fading into it. A
                          // fixed resting pill leaves a second capsule inside
                          // the held glass, especially during release.
                          child: Transform.scale(
                            scaleX:
                                (1 + _heldWidthGrowth * pressProgress) *
                                (1 + deviation),
                            scaleY:
                                (1 + _heldHeightGrowth * pressProgress) *
                                (1 - deviation),
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
                                border: outlines
                                    ? Border.all(
                                        color: scheme.onSurface.withValues(
                                          alpha: 0.05 * restingOpacity,
                                        ),
                                        width: 0.5,
                                      )
                                    : null,
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
                  _buildItems(selected),
                ),
                // The lens must sample the foreground as well as the page.
                // Below the icons it would look like a rim on a flat backdrop.
                if (lensEnabled && selected >= 0 && selected < count)
                  _interactionLens(
                    selected,
                    count,
                    pressProgress,
                    outlines,
                    deviation,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return widget.interactionBuilder?.call(context, pressProgress, content) ??
        content;
  }
}
