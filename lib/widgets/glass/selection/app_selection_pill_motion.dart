part of 'app_selection_pill.dart';

extension _AppSelectionPillStatePart1 on _AppSelectionPillState {
  Future<void> _loadMaskProgram() async {
    try {
      final program =
          _loadedSelectionMaskProgram ??
          await (_selectionMaskProgram ??= ui.FragmentProgram.fromAsset(
            'assets/shaders/app_selection_mask.frag',
          ));
      _loadedSelectionMaskProgram = program;
      if (mounted) _rebuild(() => _maskProgram = program);
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
    if (_motion.deviation != before) _rebuild(() {});
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
    _rebuild(() {
      _dragIndex = logical;
      _dragAlignment = Directionality.of(context) == TextDirection.rtl
          ? -position
          : position;
    });
    if (_pressed) _startMotion();
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
