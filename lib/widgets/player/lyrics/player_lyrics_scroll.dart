part of 'player_lyrics.dart';

extension _SyncedLyricsViewStatePart1 on _SyncedLyricsViewState {
  bool get _visible =>
      widget.isActive &&
      _tickerEnabled &&
      switch (WidgetsBinding.instance.lifecycleState) {
        null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
        _ => false,
      };
  void _stopScrollMotion() {
    _scrollMotion.stop();
    _scrollMotion.value = 1;
  }

  void _startScrollMotion(int row, double distance) {
    if (distance.abs() < 0.5 ||
        widget.seekPreview.value != null ||
        MediaQuery.disableAnimationsOf(context)) {
      _stopScrollMotion();
      return;
    }
    _rebuild(() {
      _scrollMotionDistance = distance;
      _scrollMotionFocus = row;
    });
    _scrollMotion.forward(from: 0);
  }

  void _revealTick() {
    if (mounted) _rebuild(() {});
  }

  List<double> get _rowVisibility {
    final progress = Curves.easeInOutCubic.transform(_rowReveal.value);
    if (progress == 1 || identical(_revealFrom, _revealTo)) return _revealTo;
    return _LyricRowVisibility(_revealFrom, _revealTo, progress);
  }

  void _updateRowVisibility({bool immediate = false, bool sameFocus = false}) {
    _preserveRevealAnchor = sameFocus;
    final target = List.generate(_lines.length, (index) {
      final line = _lines[index];
      if (line.text.isEmpty) return _activeLines.contains(index) ? 1.0 : 0.0;
      if (line.isBackground) return index <= _active ? 1.0 : 0.0;
      return 1.0;
    });
    if (immediate || MediaQuery.disableAnimationsOf(context)) {
      _rowReveal.stop();
      _revealFrom = target;
      _revealTo = target;
      return;
    }
    if (listEquals(target, _revealTo)) return;
    _revealFrom = List.of(_rowVisibility);
    _revealTo = target;
    _rowReveal.forward(from: 0);
  }

  double get _focusInset =>
      (MediaQuery.sizeOf(context).height * 0.06).clamp(16.0, 48.0);
  void _resetLineKeys() {
    _stopScrollMotion();
    _measurementTimer?.cancel();
    _measurementTimer = null;
    _measurementPainter?.dispose();
    _measurementPainter = null;
    _measureRow = null;
    _unmeasuredRows.clear();
    _changedMeasurementRows.clear();
    _hasStarted = false;
    _lineExtents = null;
    _lineLayoutKey = null;
    _lines = lyricsWithDisplayEnds(lyricsTimelineWithGaps(widget.lyrics.lines));
    _timeline = LyricTimelineIndex(_lines);
    _rowReveal.stop();
    _revealFrom = _revealTo = [
      for (final line in _lines)
        if (line.isBackground || line.text.isEmpty) 0.0 else 1.0,
    ];
    _targetLineExtents = null;
    _extentGeometry = null;
    _extentGeometryKey = null;
    _displayLayout = LyricDisplayLayout(_lines);
    _lineKeys = List<GlobalKey>.generate(
      _lines.length,
      (index) => GlobalKey(debugLabel: 'lyric-line-$index'),
      growable: false,
    );
  }

  void _syncPositionSubscription({bool resetUserScroll = true}) {
    _positionSubscription?.close();
    _playingSubscription?.close();
    _loadingSubscription?.close();
    _lineBoundaryTimer?.cancel();
    _positionSubscription = null;
    _playingSubscription = null;
    _loadingSubscription = null;
    if (!_visible) {
      _userScrollIdleTimer?.cancel();
      _measurementTimer?.cancel();
      _measurementTimer = null;
      _stopScrollMotion();
      _rowReveal.stop();
      return;
    }
    _userScrollIdleTimer?.cancel();
    if (resetUserScroll) _userScrolling = false;
    if (_userScrolling) _scheduleUserScrollReturn();
    _scheduleLineMeasurements();

    final position = _displayPosition;
    _playing = ref.read(playbackPlayingProvider);
    _loading = ref.read(playbackLoadingProvider);
    _active = _activeIndexAt(position);
    _activeLines = _timeline.activeIndices(position, _active);
    _focus = _focusFor(_active, _activeLines, position);
    _updateRowVisibility(immediate: true);
    _activeTransitionPosition = position;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _visible) {
        unawaited(_maybeAutoScroll(_active, immediate: true));
      }
    });
    _scheduleNextLine(position);
    _positionSubscription = ref.listenManual<Duration>(
      playbackPositionProvider,
      (previous, next) {
        if (widget.seekPreview.value != null) return;
        final active = _activeIndexAt(next);
        _setActiveLine(active, position: next);
        _scheduleNextLine(next);
      },
    );
    _playingSubscription = ref.listenManual<bool>(playbackPlayingProvider, (
      previous,
      next,
    ) {
      _playing = next;
      final position = _displayPosition;
      _setActiveLine(_activeIndexAt(position), position: position);
      _scheduleNextLine(position);
    });
    _loadingSubscription = ref.listenManual<bool>(playbackLoadingProvider, (
      previous,
      next,
    ) {
      _loading = next;
      final position = _displayPosition;
      _setActiveLine(_activeIndexAt(position), position: position);
      _scheduleNextLine(position);
    });
  }

  Duration get _displayPosition =>
      widget.seekPreview.value ?? ref.read(playbackPositionProvider);
  void _scheduleUserScrollReturn() {
    _userScrollIdleTimer?.cancel();
    if (!_visible) return;
    _userScrollIdleTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || !_visible) return;
      _userScrolling = false;
      unawaited(_maybeAutoScroll(_active));
    });
  }

  void _previewChanged() {
    if (!mounted || !_visible) return;
    final position = _displayPosition;
    final wasUserScrolling = _userScrolling;
    _userScrolling = false;
    _userScrollIdleTimer?.cancel();
    final active = _activeIndexAt(position);
    if (active == _active && (wasUserScrolling || active < 0)) {
      unawaited(_maybeAutoScroll(active));
    }
    _setActiveLine(active, position: position);
    _scheduleNextLine(position);
  }

  int _activeIndexAt(Duration position) {
    // Scrubbing is an explicit preview, even at zero or while audio buffers.
    if (widget.seekPreview.value != null) {
      return LyricsParser.activeIndex(_lines, position);
    }
    {
      final playback = ref.read(playbackStateProvider).value;
      if (playback?.processingState == AudioProcessingState.loading ||
          playback?.processingState == AudioProcessingState.buffering) {
        return -1;
      }
      _hasStarted =
          _hasStarted || playback?.playing == true || position > Duration.zero;
      if (!_hasStarted) return -1;
    }
    return LyricsParser.activeIndex(_lines, position);
  }

  /// The scroll anchor for [active]. When the next line starts while the
  /// previous one is still being sung, the view holds on the earlier line
  /// until its timed end, so both stay fully visible instead of the unfinished
  /// one scrolling away. Only the directly preceding lead line can hold.
  int _focusFor(int active, Set<int> activeLines, Duration position) {
    if (active < 0) return -1;
    final focus = _displayLayout.focusForLine[active];
    final start = _lines[focus].time;
    for (var i = focus - 1; i >= 0; i--) {
      final line = _lines[i];
      if (line.isBackground || line.time >= start) continue;
      if (line.text.isEmpty) return focus;
      final end = line.end;
      final held = _displayLayout.focusForLine[i];
      return activeLines.contains(i) && end != null && end > position
          ? held
          : focus;
    }
    return focus;
  }

  void _setActiveLine(int active, {required Duration position}) {
    if (!mounted) return;
    final activeLines = _timeline.activeIndices(position, active);
    final indexChanged = active != _active;
    final previousFocus = _focus;
    if (!indexChanged &&
        activeLines.length == _activeLines.length &&
        activeLines.containsAll(_activeLines)) {
      return;
    }
    final focus = _focusFor(active, activeLines, position);
    _rebuild(() {
      _active = active;
      _activeLines = activeLines;
      _focus = focus;
      _activeTransitionPosition = position;
      _updateRowVisibility(sameFocus: focus >= 0 && focus == previousFocus);
    });
    if (focus == previousFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _visible && active == _active) {
        unawaited(_maybeAutoScroll(active));
      }
    });
  }

  void _scheduleNextLine(Duration position) {
    _lineBoundaryTimer?.cancel();
    if (!_visible ||
        !_playing ||
        _loading ||
        widget.seekPreview.value != null) {
      return;
    }

    final lines = _lines;
    final dueIndex = syncedLyricsDueLineIndex(
      lineStarts: _timeline.starts,
      currentIndex: _active,
      position: position,
    );
    _setActiveLine(dueIndex, position: position);

    final nextIndex = dueIndex + 1;
    Duration? nextBoundary = nextIndex < lines.length
        ? lines[nextIndex].time
        : null;
    for (final index in _activeLines) {
      final end = lines[index].end;
      if ((index != dueIndex ||
              lines[index].voice != null ||
              lines[index].isBackground) &&
          end != null &&
          end > position &&
          (nextBoundary == null || end < nextBoundary)) {
        nextBoundary = end;
      }
    }
    if (nextBoundary == null) return;
    final boundary = nextBoundary;
    _lineBoundaryTimer = Timer(boundary - position, () {
      if (!mounted || !_visible || !_playing || _loading) return;
      // A late callback catches up to the audio clock instead of treating
      // its scheduled boundary as the current position.
      final now = _displayPosition;
      _scheduleNextLine(now > boundary ? now : boundary);
    });
  }

  void _measureAppLines(BuildContext context, double width) {
    final style = _appLyricStyle(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final key = (width, style, scaler, direction, locale);
    if (_lineLayoutKey == key) {
      _measureVisibleRows();
      _scheduleLineMeasurements();
      return;
    }
    _lineLayoutKey = key;
    _measurementTimer?.cancel();
    _measurementTimer = null;
    _measurementPainter?.dispose();
    final painter = _measurementPainter = TextPainter(
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
    );
    _lineMeasurements = List.filled(_lines.length, (
      _SyncedLyricsViewState._estimatedLyricExtent,
      0.0,
      0.0,
    ));
    _pronunciationLayouts = List.filled(_lines.length, null);
    _unmeasuredRows
      ..clear()
      ..addAll(Iterable.generate(_lines.length));
    _changedMeasurementRows.clear();
    _measurementRevision++;
    _measureRow = (row) {
      if (!_unmeasuredRows.remove(row)) return;
      _changedMeasurementRows.add(row);
      final index = _displayLayout.lineOrder[row];
      final line = _lines[index];
      if (line.text.isEmpty) {
        _lineMeasurements[row] = (56, 0, 0);
        _measurementRevision++;
        return;
      }
      // Rows lay out in their own direction; measure them the same way.
      final lineDirection = lyricLineDirection(line.text, direction);
      painter.textDirection = lineDirection;
      painter.text = TextSpan(
        text: line.text,
        style: _appLyricStyle(context, background: line.isBackground),
      );
      painter.layout(maxWidth: width);
      final padding = _linePadding(index).vertical;
      var height = painter.height + padding;
      var pronunciationHeight = 0.0;
      var translationHeight = 0.0;
      LyricPronunciationLayout? pronunciationLayout;
      for (final (text, style, _, translation) in _lyricSupplements(
        context,
        line,
      )) {
        painter.text = TextSpan(text: text, style: style);
        painter.layout(maxWidth: width);
        if (translation) {
          translationHeight = 6 + painter.height;
        } else {
          pronunciationHeight = 6 + painter.height;
          final aligned = LyricPronunciationLayout.measure(
            line: line,
            primaryStyle: _appLyricStyle(
              context,
              background: line.isBackground,
            ),
            pronunciationStyle: style,
            maxWidth: width,
            textScaler: scaler,
            textDirection: lineDirection,
            locale: locale,
          );
          if (aligned != null) {
            pronunciationLayout = aligned;
            height = aligned.primaryHeight + padding;
            pronunciationHeight = aligned.pronunciationHeight;
          }
        }
      }
      _lineMeasurements[row] = (height, pronunciationHeight, translationHeight);
      _pronunciationLayouts[index] = pronunciationLayout;
      _measurementRevision++;
    };
    if (_lines.length <= 128) {
      while (_unmeasuredRows.isNotEmpty) {
        _measureRow!(_unmeasuredRows.first);
      }
    } else {
      _measureVisibleRows();
    }
    _scheduleLineMeasurements();
  }
}
