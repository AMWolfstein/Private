import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:sistrum/theme/app_glass_levels.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/widgets/glass/thumb/app_liquid_backdrop.dart';
import 'package:sistrum/widgets/glass/selection/app_selection_foreground.dart';
import 'package:sistrum/widgets/glass/selection/app_selection_shared.dart';

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

  Future<void> _loadMaskProgram() async {
    try {
      final program =
          _loadedSelectionMaskProgram ??
          await (_selectionMaskProgram ??= ui.FragmentProgram.fromAsset(
            'assets/shaders/app_selection_mask.frag',
          ));
      _loadedSelectionMaskProgram = program;
      if (mounted) setState(() => _maskProgram = program);
    } catch (error) {
      debugPrint('Sistrum selection mask unavailable: $error');
    }
  }

  /// Samples the dragged pill's centre each frame; drags move it 1:1, so
  /// the model sees real finger motion rather than the tap glide.
  void _startMotion() {
    if (_motion.isTracking) return;
    _motion.start();
    _motionLast = null;
    final ticker = _motionTicker ??= createTicker(_trackMotion);
    if (!ticker.isActive) ticker.start();
  }

  void _stopMotion() {
    if (!_motion.isTracking) return;
    // Reset at release, masked by the lens contracting, as in the package.
    _motion.stop();
    _motionTicker?.stop();
  }

  void _trackMotion(Duration elapsed) {
    final alignment = _dragAlignment;
    final count = widget.labels.length;
    if (alignment == null || count == 0) return;
    final last = _motionLast ?? elapsed;
    _motionLast = elapsed;
    final dt = (elapsed - last).inMicroseconds / 1e6;
    if (dt <= 0) return;
    final item = _laneWidth / count;
    final x = (alignment + 1) / 2 * (_laneWidth - item) + item / 2;
    final before = _motion.deviation;
    _motion.track(Offset(x, 0), now: elapsed.inMicroseconds / 1e6, dt: dt);
    if (_motion.deviation != before) setState(() {});
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

  void _preview(double x, double width) {
    if (width <= 0 || widget.labels.isEmpty) return;
    final visual = (x / width * widget.labels.length).floor().clamp(
      0,
      widget.labels.length - 1,
    );
    final logical = Directionality.of(context) == TextDirection.rtl
        ? widget.labels.length - 1 - visual
        : visual;
    final halfItem = width / widget.labels.length / 2;
    final position = width <= halfItem * 2
        ? 0.0
        : ((x.clamp(halfItem, width - halfItem) - halfItem) /
                      (width - 2 * halfItem)) *
                  2 -
              1;
    _laneWidth = width;
    setState(() {
      _dragIndex = logical;
      _dragAlignment = Directionality.of(context) == TextDirection.rtl
          ? -position
          : position;
    });
    if (_pressed) _startMotion();
  }

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

  Widget _buildItems(int selected) {
    // Masked foreground keeps the same icons and labels during a press or
    // drag. Only its shader scope and the lens depend on that animation.
    final itemSelection = widget.selectionColor == null ? selected : null;
    if (_itemsSelected != itemSelection) _items = null;
    _itemsSelected = itemSelection;
    return _items ??= Row(
      key: _foregroundKey,
      children: [
        for (var index = 0; index < widget.labels.length; index++)
          Expanded(
            child: Semantics(
              button: true,
              selected: index == widget.selectedIndex,
              label: widget.labels[index],
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(kAppSelectionPillRadius),
                  // The moving pill supplies press feedback. An ink highlight
                  // would leave a colored patch where the drag started.
                  splashFactory: widget.selectionColor == null
                      ? null
                      : NoSplash.splashFactory,
                  highlightColor: widget.selectionColor == null
                      ? null
                      : Colors.transparent,
                  onTap: () => widget.onChanged(index),
                  child: ExcludeSemantics(
                    child: _item(context, index, selected),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _item(BuildContext context, int index, int selected) {
    final child = widget.itemBuilder(
      context,
      index,
      widget.selectionColor == null && index == selected,
    );
    return widget.maskItemForeground
        ? AppSelectionForeground(child: child)
        : child;
  }

  Widget _foreground(
    int selected,
    int count,
    double pressProgress,
    Widget child,
  ) {
    final color = widget.selectionColor;
    if (color == null) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(
        end:
            _dragAlignment ??
            (count == 1 ? 0 : -1 + 2 * selected / (count - 1)),
      ),
      duration:
          _dragAlignment != null || MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, alignment, child) => AppSelectionForegroundScope(
        rowKey: _foregroundKey,
        alignment: Directionality.of(context) == TextDirection.rtl
            ? -alignment
            : alignment,
        count: count,
        scaleX: 1 + _heldWidthGrowth * pressProgress,
        scaleY: 1 + _heldHeightGrowth * pressProgress,
        program: _maskProgram,
        color: selected >= 0 && selected < count
            ? color
            : color.withValues(alpha: 0),
        child: child!,
      ),
      child: child,
    );
  }

  Widget _interactionLens(
    int selected,
    int count,
    double progress,
    bool outlines,
    double deviation,
  ) => Positioned.fill(
    child: IgnorePointer(
      child: AnimatedAlign(
        duration: _dragAlignment != null
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: AlignmentDirectional(
          _dragAlignment ?? (count == 1 ? 0 : -1 + 2 * selected / (count - 1)),
          0,
        ),
        child: FractionallySizedBox(
          widthFactor: 1 / count,
          heightFactor: 1,
          child: Transform.scale(
            scaleX: (1 + _heldWidthGrowth * progress) * (1 + deviation),
            scaleY: (1 + _heldHeightGrowth * progress) * (1 - deviation),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kAppSelectionPillRadius),
              child: LiquidGlassBatch.exclude(
                child: AppLiquidBackdrop(
                  borderRadius: BorderRadius.circular(kAppSelectionPillRadius),
                  // Colour split is a full-glass effect; a lite pill has none.
                  dispersion:
                      ref.watch(appGlassLevelProvider) == AppGlassLevel.liquid
                      ? appGlassClarity(
                          ref.watch(appGlassClarityLevelProvider),
                        ).dispersion
                      : 0,
                  interaction: true,
                  progress: progress,
                  blurSigma: 0,
                  // A broader bevel makes the held lens visible as it crosses
                  // the icons, while leaving its center undistorted.
                  refractionDepth: 0.18,
                  refractionWidth: 18,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        kAppSelectionPillRadius,
                      ),
                      color: Colors.white.withValues(
                        alpha:
                            progress *
                            (Theme.of(context).brightness == Brightness.light
                                ? 0.24
                                : 0.08),
                      ),
                      border: outlines
                          ? Border.all(
                              color: Colors.white.withValues(
                                alpha: 0.6 * progress,
                              ),
                              width: 0.75,
                            )
                          : null,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
