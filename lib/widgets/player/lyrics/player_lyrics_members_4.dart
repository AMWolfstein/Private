part of 'player_lyrics.dart';

extension _SyncedLyricsViewStatePart4 on _SyncedLyricsViewState {
  Widget _revealRow(
    int index,
    double visibility,
    TextAlign align,
    Widget child,
  ) {
    final AlignmentGeometry alignment = align == TextAlign.end
        ? AlignmentDirectional.topEnd
        : align == TextAlign.center
        ? Alignment.topCenter
        : AlignmentDirectional.topStart;
    // A fixed-extent row is already shrinking. Measure its contents at full
    // height so fitting does not scale it twice.
    final fullHeight = OverflowBox(
      minHeight: 0,
      maxHeight: double.infinity,
      fit: OverflowBoxFit.deferToChild,
      alignment: Alignment.topCenter,
      child: child,
    );
    return KeyedSubtree(
      key: _lineKeys[index],
      child: !_lines[index].isBackground && _lines[index].text.isNotEmpty
          ? child
          : IgnorePointer(
              ignoring: visibility < 1,
              child: _lines[index].isBackground
                  ? LyricBackingTransition(
                      visibility: visibility,
                      alignment: alignment,
                      child: fullHeight,
                    )
                  : LyricSupplementTransition(
                      visibility: visibility,
                      alignment: alignment,
                      child: fullHeight,
                    ),
            ),
    );
  }

  EdgeInsets _linePadding(int index) {
    final row = _displayLayout.rowForLine[index];
    final order = _displayLayout.lineOrder;
    final hasBackingBelow =
        row + 1 < order.length &&
        _lines[order[row + 1]].isBackground &&
        _displayLayout.leadForLine[order[row + 1]] ==
            _displayLayout.leadForLine[index];
    return EdgeInsets.only(
      top: _lines[index].isBackground ? 6 : context.tokens.lyricsLinePaddingV,
      bottom: hasBackingBelow ? 0 : context.tokens.lyricsLinePaddingV,
    );
  }
}
