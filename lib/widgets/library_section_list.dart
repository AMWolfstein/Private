import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sistrum/widgets/pinned_section_sliver_list.dart';

final _letterPattern = RegExp(r'[\p{L}]', unicode: true);
final _monthFormatters = <String, DateFormat>{};

String librarySectionInitial(String value) {
  final text = value.trim();
  if (text.isEmpty) return '#';
  final first = text.characters.first;
  return _letterPattern.hasMatch(first) ? first.toUpperCase() : '#';
}

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
  });
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
  List<({String label, int start, int offset})> _sections = [];
  List<int> _headers = [];
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _group();
  }

  @override
  void didUpdateWidget(covariant SectionedLibrarySliverList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.items, widget.items) ||
        oldWidget.groupingKey != widget.groupingKey) {
      _group();
    }
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
