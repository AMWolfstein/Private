import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sistrum/widgets/collection/pinned_section_sliver_list.dart';

export 'package:sistrum/utils/text/library_initial.dart';

final _monthFormatters = <String, DateFormat>{};

String librarySectionMonth(DateTime date, String locale) =>
    (_monthFormatters[locale] ??= DateFormat.yMMMM(locale)).format(date);

/// Lazy section headers share the row delegate and retain only the pinned label.
/// Items remain in the repository's paged sort order; no full-library preload.
class SectionedLibrarySliverList<T> extends StatefulWidget {
  const SectionedLibrarySliverList({
    super.key,
    required this.items,
    required this.groupingKey,
    required this.labelOf,
    required this.rowBuilder,
    this.controller,
    this.revealPadding = 0,
  });
  final AppLibrarySectionController? controller;
  final double revealPadding;
  final List<T> items;
  final Object groupingKey;
  final String? Function(T) labelOf;
  final Widget Function(BuildContext, int) rowBuilder;

  @override
  State<SectionedLibrarySliverList<T>> createState() =>
      _SectionedLibrarySliverListState<T>();
}

class _SectionedLibrarySliverListState<T>
    extends State<SectionedLibrarySliverList<T>> {
  final _sliverKey = GlobalKey();
  List<({String label, int start, int offset})> _sections = [];
  List<int> _headers = [];
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _group();
    widget.controller?._reveal = _reveal;
  }

  @override
  void didUpdateWidget(covariant SectionedLibrarySliverList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller?._reveal == _reveal) {
        oldWidget.controller?._reveal = null;
      }
      widget.controller?._reveal = _reveal;
    }
    if (!identical(oldWidget.items, widget.items) ||
        oldWidget.groupingKey != widget.groupingKey) {
      _group();
    }
  }

  @override
  void dispose() {
    if (widget.controller?._reveal == _reveal) {
      widget.controller?._reveal = null;
    }
    super.dispose();
  }

  Future<bool> _reveal(int item, bool Function() current) async {
    if (item < 0 || item >= widget.items.length) return false;
    final section = _sections.lastWhere((s) => s.start <= item);
    final target =
        section.offset + item - section.start + (section.label.isEmpty ? 0 : 1);
    for (var attempt = 0; attempt < 16 && mounted && current(); attempt++) {
      final context = _sliverKey.currentContext;
      if (context == null || !context.mounted) return false;
      final sliver = context.findRenderObject() as RenderSliverList;
      final position = Scrollable.of(context).position;
      final first = sliver.firstChild;
      if (first == null) return false;
      RenderBox? child = first;
      RenderBox last = first;
      while (child != null) {
        last = child;
        if (sliver.indexOf(child) == target) {
          final viewport = RenderAbstractViewport.of(child);
          final offset =
              viewport.getOffsetToReveal(child, 0).offset -
              widget.revealPadding;
          position.jumpTo(
            offset.clamp(position.minScrollExtent, position.maxScrollExtent),
          );
          return true;
        }
        child = sliver.childAfter(child);
      }
      final firstIndex = sliver.indexOf(first);
      final lastIndex = sliver.indexOf(last);
      final firstOffset = sliver.childScrollOffset(first) ?? 0;
      final lastOffset = sliver.childScrollOffset(last) ?? firstOffset;
      final average =
          (lastOffset - firstOffset + last.size.height) /
          (lastIndex - firstIndex + 1);
      final viewport = RenderAbstractViewport.of(sliver.parent);
      final origin = viewport.getOffsetToReveal(first, 0).offset - firstOffset;
      final estimate = origin + firstOffset + (target - firstIndex) * average;
      position.jumpTo(
        estimate.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
      await WidgetsBinding.instance.endOfFrame;
    }
    return false;
  }

  void _group() {
    _sections = [];
    _headers = [];
    _count = 0;
    String? previous;
    for (var index = 0; index < widget.items.length; index++) {
      final label = widget.labelOf(widget.items[index]) ?? '';
      if (index == 0 || label != previous) {
        _sections.add((label: label, start: index, offset: _count));
        if (label.isNotEmpty) _headers.add(_count++);
        previous = label;
      }
      _count++;
    }
  }

  @override
  Widget build(BuildContext context) => PinnedSectionSliverList(
    key: _sliverKey,
    headerIndexes: _headers,
    delegate: SliverChildBuilderDelegate((context, index) {
      var low = 0;
      var high = _sections.length;
      while (low < high) {
        final middle = (low + high) ~/ 2;
        if (_sections[middle].offset <= index) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      final section = _sections[low - 1];
      final offset = index - section.offset;
      if (section.label.isNotEmpty && offset == 0) {
        final theme = Theme.of(context);
        return ColoredBox(
          color: theme.scaffoldBackgroundColor,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            child: Semantics(
              header: true,
              child: Text(
                section.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
        );
      }
      return widget.rowBuilder(
        context,
        section.start + offset - (section.label.isNotEmpty ? 1 : 0),
      );
    }, childCount: _count),
  );
}

/// Seeks lazily built rows without retaining a key for every library item.
class AppLibrarySectionController {
  Future<bool> Function(int, bool Function())? _reveal;
  int _generation = 0;
  void cancel() => _generation++;
  Future<bool> reveal(int index) async {
    final generation = ++_generation;
    return await _reveal?.call(index, () => generation == _generation) ?? false;
  }
}
