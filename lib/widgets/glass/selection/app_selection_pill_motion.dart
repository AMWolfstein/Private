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
    _rebuild(() {
      _dragIndex = logical;
      _dragAlignment = Directionality.of(context) == TextDirection.rtl
          ? -position
          : position;
    });
    // Under the finger the pill is placed, not sprung.
    final count = widget.labels.length;
    _slideTarget = null;
    _at.stop();
    _at.value = count == 1 ? 0 : (_dragAlignment! + 1) / 2 * (count - 1);
  }

  Widget _buildItems(int selected) {
    // Masked foreground keeps the same icons and labels during a press or
    // drag. Only its shader scope and the glass depend on that animation.
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
    double stretch,
    Widget child,
  ) {
    final color = widget.selectionColor;
    if (color == null) return child;
    final alignment = _alignmentOf(count);
    return AppSelectionForegroundScope(
      rowKey: _foregroundKey,
      alignment: Directionality.of(context) == TextDirection.rtl
          ? -alignment
          : alignment,
      count: count,
      scaleX: (1 + _heldWidthGrowth * pressProgress) * (1 + stretch),
      scaleY: (1 + _heldHeightGrowth * pressProgress) / (1 + stretch),
      program: _maskProgram,
      color: selected >= 0 && selected < count
          ? color
          : color.withValues(alpha: 0),
      child: child,
    );
  }

  /// The held pill: a blur, a light veil and a rim, sliding to the selected
  /// item. It exists only while a press is in progress.
  Widget _heldGlass(int selected, int count, double lift, double stretch) {
    // The spring rises past held for a moment: the size follows it, the
    // optics and the veil stop at fully there.
    final progress = lift.clamp(0.0, 1.0);
    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: AlignmentDirectional(_alignmentOf(count), 0),
          child: FractionallySizedBox(
            widthFactor: 1 / count,
            heightFactor: 1,
            child: Transform.scale(
              scaleX: (1 + _heldWidthGrowth * lift) * (1 + stretch),
              scaleY: (1 + _heldHeightGrowth * lift) / (1 + stretch),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(kAppSelectionPillRadius),
                child: GlassSurface(
                  presence: progress,
                  borderRadius: BorderRadius.circular(kAppSelectionPillRadius),
                  finish: kAppLiquidGlassFinish,
                  labelled: false,
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
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.6 * progress),
                        width: 0.75,
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
