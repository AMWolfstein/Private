import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A persistent, directional letter rail. Pointer travel selects letters rather
/// than estimating song positions; callers own paging and exact row revelation.
class AppLibraryAlphabetIndex extends StatefulWidget {
  const AppLibraryAlphabetIndex({
    super.key,
    required this.labels,
    required this.onSelected,
    required this.child,
    this.topPadding = 0,
    this.bottomPadding = 0,
  });
  final List<String> labels;
  final ValueChanged<String> onSelected;
  final Widget child;
  final double topPadding, bottomPadding;

  @override
  State<AppLibraryAlphabetIndex> createState() =>
      _AppLibraryAlphabetIndexState();
}

class _AppLibraryAlphabetIndexState extends State<AppLibraryAlphabetIndex> {
  String? _selected;
  Timer? _clear;

  @override
  void dispose() {
    _clear?.cancel();
    super.dispose();
  }

  void _select(String label) {
    if (_selected == label) return;
    _clear?.cancel();
    setState(() => _selected = label);
    HapticFeedback.selectionClick();
    widget.onSelected(label);
  }

  void _end() {
    _clear?.cancel();
    _clear = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _selected = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.labels.isEmpty) return widget.child;
    final colors = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 30),
          child: widget.child,
        ),
        PositionedDirectional(
          end: 0,
          top: widget.topPadding,
          bottom: widget.bottomPadding,
          width: 30,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = math.min(
                constraints.maxHeight,
                widget.labels.length * 18.0,
              );
              void at(Offset position) {
                if (height <= 0) return;
                final index = (position.dy / height * widget.labels.length)
                    .floor()
                    .clamp(0, widget.labels.length - 1);
                _select(widget.labels[index]);
              }

              return Center(
                child: SizedBox(
                  height: height,
                  width: 30,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) => at(details.localPosition),
                    onTapUp: (_) => _end(),
                    onTapCancel: _end,
                    onVerticalDragStart: (details) => at(details.localPosition),
                    onVerticalDragUpdate: (details) =>
                        at(details.localPosition),
                    onVerticalDragEnd: (_) => _end(),
                    onVerticalDragCancel: _end,
                    child: Column(
                      children: [
                        for (final label in widget.labels)
                          Expanded(
                            child: Semantics(
                              button: true,
                              label: label,
                              selected: _selected == label,
                              onTap: () {
                                _select(label);
                                _end();
                              },
                              child: ExcludeSemantics(
                                child: Center(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: colors.primary,
                                      ),
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
              );
            },
          ),
        ),
        if (_selected != null)
          PositionedDirectional(
            end: 42,
            top: null,
            bottom: widget.bottomPadding + 24,
            child: IgnorePointer(
              child: Material(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _selected!,
                    style: TextStyle(
                      fontSize: 28,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
