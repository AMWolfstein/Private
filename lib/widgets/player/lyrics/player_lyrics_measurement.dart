part of 'player_lyrics.dart';

extension _SyncedLyricsViewStatePart2 on _SyncedLyricsViewState {
  void _measureVisibleRows() {
    final measure = _measureRow;
    if (measure == null || _unmeasuredRows.isEmpty) return;
    final extents = _lineExtents;
    final anchor = _scroll.hasClients && extents != null
        ? _rowAtScrollOffset(extents, _scroll.offset)
        : _focus < 0
        ? 0
        : _displayLayout.rowForLine[_focus];
    // Exact geometry for the viewport and a small overscan. The rest is
    // prepared in bounded idle batches, including hidden supplements.
    final first = (anchor - 4).clamp(0, _lines.length);
    final last = (anchor + 28).clamp(0, _lines.length);
    for (var row = first; row < last; row++) {
      measure(row);
    }
  }

  void _scheduleLineMeasurements() {
    if (!_visible || _measurementTimer != null || _unmeasuredRows.isEmpty) {
      return;
    }
    _measurementTimer = Timer(const Duration(milliseconds: 16), () {
      _measurementTimer = null;
      if (!mounted || !_visible || _unmeasuredRows.isEmpty) return;
      if ((_scroll.hasClients && _scroll.position.isScrollingNotifier.value) ||
          _rowReveal.isAnimating ||
          _scrollMotion.isAnimating) {
        _scheduleLineMeasurements();
        return;
      }
      final budget = Stopwatch()..start();
      var measured = 0;
      while (_unmeasuredRows.isNotEmpty &&
          measured < 32 &&
          (measured == 0 || budget.elapsedMicroseconds < 2000)) {
        _measureRow!(_unmeasuredRows.first);
        measured++;
      }
      _rebuild(() {});
      _scheduleLineMeasurements();
    });
  }

  void _scheduleVisibleMeasurements(double offset) {
    final extents = _lineExtents;
    if (_unmeasuredRows.isEmpty ||
        extents == null ||
        _measurementFramePending ||
        !_visible) {
      return;
    }
    final first = _rowAtScrollOffset(extents, offset);
    final last = (first + 28).clamp(0, _lines.length);
    if (!Iterable.generate(
      last - first,
      (index) => first + index,
    ).any(_unmeasuredRows.contains)) {
      return;
    }
    _measurementFramePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementFramePending = false;
      if (mounted && _visible) _rebuild(() {});
    });
  }

  int _rowAtScrollOffset(_LyricExtentSnapshot extents, double offset) =>
      extents.rowAtOffset((offset - _focusInset).clamp(0.0, double.infinity));
  Future<void> _maybeAutoScroll(int index, {bool immediate = false}) async {
    // A short intro may have no countdown row. Still return to the first
    // upcoming lyric when the user scrubs back before any vocals.
    if (index < 0 && widget.seekPreview.value != null) index = 0;
    if (!_visible ||
        _userScrolling ||
        index < 0 ||
        index >= _lines.length ||
        !_scroll.hasClients) {
      return;
    }
    index = index == _active && _focus >= 0
        ? _focus
        : _displayLayout.focusForLine[index];
    final row = _displayLayout.rowForLine[index];
    final seeking = widget.seekPreview.value != null;
    final duration = immediate || MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : seeking
        ? const Duration(milliseconds: 220)
        : LyricScrollMotion.scrollDuration;
    // Scrubbing follows the finger quickly; playback eases between lines.
    final curve = seeking ? Curves.easeOutCubic : LyricScrollMotion.scrollCurve;
    if (duration == Duration.zero) _stopScrollMotion();
    final extents = _targetLineExtents;
    if (extents != null && row < extents.length) {
      // Rows past the viewport are estimated until they are built and
      // measured, so the first offset can miss a tall line. Re-aim from the
      // measured geometry a few times, until the offset stops moving.
      for (var pass = 0; pass < 4; pass++) {
        final current = _targetLineExtents;
        if (current == null || row >= current.length || !_scroll.hasClients) {
          break;
        }
        final position = _scroll.position;
        final offset = current
            .offsetForRow(row)
            .clamp(position.minScrollExtent, position.maxScrollExtent);
        if (pass > 0 && (offset - position.pixels).abs() < 1) break;
        if (duration == Duration.zero || pass > 0) {
          _scroll.jumpTo(offset);
        } else {
          _startScrollMotion(row, offset - position.pixels);
          await _scroll.animateTo(offset, duration: duration, curve: curve);
        }
        if (duration == Duration.zero) break;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !_visible || _userScrolling || _active != _focus) {
          return;
        }
      }
      return;
    }
    if (index < _lineKeys.length) {
      final lineContext = _lineKeys[index].currentContext;
      if (lineContext != null) {
        final object = lineContext.findRenderObject();
        final viewport = object == null
            ? null
            : RenderAbstractViewport.maybeOf(object);
        if (duration != Duration.zero && viewport != null) {
          _startScrollMotion(
            row,
            viewport.getOffsetToReveal(object!, 0.5).offset - _scroll.offset,
          );
        }
        await Scrollable.ensureVisible(
          lineContext,
          alignment: 0.5,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          duration: duration,
          curve: curve,
        );
        return;
      }
    }

    final position = _scroll.position;
    final target = syncedLyricsEstimatedOffset(
      index: row,
      estimatedLineExtent: _SyncedLyricsViewState._estimatedLyricExtent,
    );
    final clamped = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (duration == Duration.zero) {
      _scroll.jumpTo(clamped.toDouble());
    } else {
      _startScrollMotion(row, clamped - position.pixels);
      await _scroll.animateTo(
        clamped.toDouble(),
        duration: duration,
        curve: curve,
      );
    }
    if (!mounted ||
        _userScrolling ||
        (_active >= 0 && index != _focus) ||
        index >= _lineKeys.length) {
      return;
    }
    final lineContext = _lineKeys[index].currentContext;
    if (lineContext != null && lineContext.mounted) {
      await Scrollable.ensureVisible(
        lineContext,
        alignment: 0.5,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        duration: duration == Duration.zero
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }
}
