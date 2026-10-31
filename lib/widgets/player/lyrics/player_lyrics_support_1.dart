part of 'player_lyrics.dart';

class _LyricRowVisibility extends ListBase<double> {
  _LyricRowVisibility(this.from, this.to, this.progress);

  final List<double> from;
  final List<double> to;
  final double progress;

  @override
  int get length => from.length;

  @override
  set length(int value) => throw UnsupportedError('Immutable lyric visibility');

  @override
  double operator [](int index) =>
      from[index] + (to[index] - from[index]) * progress;

  @override
  void operator []=(int index, double value) =>
      throw UnsupportedError('Immutable lyric visibility');
}

/// Prefix coefficients separate text geometry from the three animation values.
/// Row reads are constant time; a Fenwick tree updates measured rows and finds
/// anchor offsets without copying the entire document on each frame/batch.
class _LyricExtentGeometry {
  _LyricExtentGeometry(
    List<(double, double, double)> measurements,
    this.order,
    this.revealFrom,
    this.revealTo,
    this.scaleForLine,
    this.paddingForLine,
  ) : starts = List.filled(measurements.length, (0, 0, 0)),
      changes = List.filled(measurements.length, (0, 0, 0)),
      prefixStarts = List.filled(measurements.length + 1, (0, 0, 0)),
      prefixChanges = List.filled(measurements.length + 1, (0, 0, 0)) {
    for (var row = 0; row < measurements.length; row++) {
      updateRow(row, measurements[row], updatePrefix: false);
      prefixStarts[row + 1] = starts[row];
      prefixChanges[row + 1] = changes[row];
    }
    for (var node = 1; node < prefixStarts.length; node++) {
      final parent = node + (node & -node);
      if (parent >= prefixStarts.length) continue;
      for (final tree in [prefixStarts, prefixChanges]) {
        final value = tree[node];
        final previous = tree[parent];
        tree[parent] = (
          previous.$1 + value.$1,
          previous.$2 + value.$2,
          previous.$3 + value.$3,
        );
      }
    }
  }

  final List<int> order;
  final List<double> revealFrom;
  final List<double> revealTo;
  final double Function(int) scaleForLine;
  final double Function(int) paddingForLine;
  final List<(double, double, double)> starts;
  final List<(double, double, double)> changes;
  final List<(double, double, double)> prefixStarts;
  final List<(double, double, double)> prefixChanges;

  void updateRow(
    int row,
    (double, double, double) measurement, {
    bool updatePrefix = true,
  }) {
    final index = order[row];
    final (primary, pronunciation, translation) = measurement;
    final scale = scaleForLine(index);
    final padding = paddingForLine(index);
    final base = padding + (primary - padding) * scale;
    final from = revealFrom[index];
    final delta = revealTo[index] - from;
    final start = (
      base * from,
      pronunciation * scale * from,
      translation * scale * from,
    );
    final change = (
      base * delta,
      pronunciation * scale * delta,
      translation * scale * delta,
    );
    if (updatePrefix) {
      _updatePrefix(prefixStarts, row, starts[row], start);
      _updatePrefix(prefixChanges, row, changes[row], change);
    }
    starts[row] = start;
    changes[row] = change;
  }

  void _updatePrefix(
    List<(double, double, double)> tree,
    int row,
    (double, double, double) previous,
    (double, double, double) next,
  ) {
    for (var node = row + 1; node < tree.length; node += node & -node) {
      final value = tree[node];
      tree[node] = (
        value.$1 + next.$1 - previous.$1,
        value.$2 + next.$2 - previous.$2,
        value.$3 + next.$3 - previous.$3,
      );
    }
  }

  (double, double, double) prefix(
    List<(double, double, double)> tree,
    int row,
  ) {
    var result = (0.0, 0.0, 0.0);
    for (var node = row; node > 0; node -= node & -node) {
      final value = tree[node];
      result = (
        result.$1 + value.$1,
        result.$2 + value.$2,
        result.$3 + value.$3,
      );
    }
    return result;
  }
}

class _LyricExtentSnapshot extends ListBase<double> {
  _LyricExtentSnapshot(this.geometry, this.visibility, this.progress);

  final _LyricExtentGeometry geometry;
  final Offset visibility;
  final double progress;

  double _value(
    (double, double, double) from,
    (double, double, double) change,
  ) =>
      from.$1 +
      change.$1 * progress +
      (from.$2 + change.$2 * progress) * visibility.dx +
      (from.$3 + change.$3 * progress) * visibility.dy;

  double offsetForRow(int row) => _value(
    geometry.prefix(geometry.prefixStarts, row),
    geometry.prefix(geometry.prefixChanges, row),
  );

  int rowAtOffset(double offset) {
    var low = 0;
    var high = length;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (offsetForRow(middle) <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  @override
  int get length => geometry.starts.length;

  @override
  set length(int value) => throw UnsupportedError('Immutable lyric extents');

  @override
  double operator [](int index) =>
      _value(geometry.starts[index], geometry.changes[index]);

  @override
  void operator []=(int index, double value) =>
      throw UnsupportedError('Immutable lyric extents');
}

Iterable<(String, TextStyle, List<LyricWord>, bool)> _lyricSupplements(
  BuildContext context,
  LyricLine line,
) sync* {
  final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
  for (final (text, translation) in [
    (line.romanization, false),
    (line.translation, true),
  ]) {
    if (text == null || text.trim().isEmpty) continue;
    yield (
      text,
      base.copyWith(
        fontSize: ((translation ? 18.0 : 22.0)) * (line.isBackground ? 0.8 : 1),
        height: 1.35,
        fontWeight: (translation ? FontWeight.w600 : FontWeight.bold),
      ),
      translation ? const <LyricWord>[] : line.romanizationWords,
      translation,
    );
  }
}

TextStyle _appLyricStyle(BuildContext context, {bool background = false}) =>
    DefaultTextStyle.of(context).style.merge(
      (Theme.of(context).textTheme.headlineSmall ?? const TextStyle()).copyWith(
        fontSize: _appLyricFontSize * (background ? 0.68 : 1),
        height: context.tokens.lyricsLineHeight,
        fontWeight: FontWeight.bold,
      ),
    );
TextAlign _lyricTextAlign(BuildContext context, LyricLine line) {
  final voice = line.voice;
  if (voice == null) {
    return TextAlign.start;
  }
  // The lead voice keeps the reading start, so duets mirror in right-to-left
  // layouts.
  if (voice.isGroup) return TextAlign.start;
  // Provider declarations can be missing or ordered by first appearance.
  // The standard V labels retain their meaning regardless of that order.
  switch (voice.id.toLowerCase()) {
    case 'v1':
    case 'v3':
      return TextAlign.start;
    case 'v2':
      return TextAlign.end;
  }
  return voice.index.isEven ? TextAlign.start : TextAlign.end;
}

Widget _withLyricSupplements(
  BuildContext context,
  LyricLine line,
  Widget primary,
  Color color, {
  required Offset visibility,
  required LyricPronunciationLayout? pronunciationLayout,
  required TextAlign textAlign,
  Widget Function(String, List<LyricWord>, TextStyle)? timedText,
  Widget Function(String, List<LyricWord>, TextStyle)? timedSupplementText,
}) {
  if (line.romanization == null && line.translation == null) return primary;
  final AlignmentGeometry alignment = switch (textAlign) {
    TextAlign.end => AlignmentDirectional.topEnd,
    TextAlign.center => Alignment.topCenter,
    _ => AlignmentDirectional.topStart,
  };
  final supplements = _lyricSupplements(context, line).toList();
  Widget withSupplements(Widget primary, {bool aligned = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      primary,
      for (final (text, style, words, translation) in supplements)
        if ((translation || !aligned) &&
            (translation ? visibility.dy : visibility.dx) > 0)
          LyricSupplementTransition(
            alignment: alignment,
            visibility: translation ? visibility.dy : visibility.dx,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: words.isNotEmpty && timedSupplementText != null
                  ? timedSupplementText(text, words, style)
                  : Text(
                      text,
                      textAlign: textAlign,
                      style: style.copyWith(
                        color: color.withValues(alpha: color.a * 0.8),
                      ),
                    ),
            ),
          ),
    ],
  );
  if (line.romanizationWords.isEmpty ||
      line.romanization?.trim().isNotEmpty != true) {
    return withSupplements(primary);
  }
  final primaryStyle = _appLyricStyle(context, background: line.isBackground);
  final pronunciationStyle = supplements
      .firstWhere((supplement) => !supplement.$4)
      .$2;
  final layout = pronunciationLayout;
  if (layout == null) return withSupplements(primary);
  return withSupplements(
    AlignedLyricPronunciation(
      layout: layout,
      visibility: visibility.dx,
      primaryStyle: primaryStyle,
      pronunciationStyle: pronunciationStyle,
      textAlign: textAlign,
      pronunciationBuilder: timedSupplementText,
      textBuilder:
          timedText ??
          (text, words, style) => Text(
            text,
            textAlign: textAlign,
            style: style.copyWith(color: color),
          ),
    ),
    aligned: true,
  );
}

class _WordHighlightedLyricLine extends ConsumerStatefulWidget {
  final LyricLine line;
  final ColorScheme colorScheme;
  final bool animate;
  final Duration initialPosition;
  final ValueListenable<Duration?> seekPreview;
  final Offset supplementVisibility;
  final LyricPronunciationLayout? pronunciationLayout;
  final TextAlign textAlign;

  const _WordHighlightedLyricLine({
    required this.line,
    required this.colorScheme,
    required this.animate,
    required this.initialPosition,
    required this.seekPreview,
    required this.supplementVisibility,
    required this.pronunciationLayout,
    required this.textAlign,
  });

  @override
  ConsumerState<_WordHighlightedLyricLine> createState() =>
      _WordHighlightedLyricLineState();
}
