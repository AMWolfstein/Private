part of 'player_lyrics.dart';

extension _SyncedLyricsViewStatePart3 on _SyncedLyricsViewState {
  Widget _buildLyrics(BuildContext context, Offset visibility) {
    final lines = _lines;
    final active = _active;
    final rowVisibility = _rowVisibility;
    final loading = _visible
        ? ref.watch(playbackLoadingProvider)
        : ref.read(playbackLoadingProvider);
    final sistrum = context.isAppTheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final blurLyrics =
        !highContrast &&
        // Every defocused line is filtered again on each playback frame.
        ref.watch(appLiquidGlassProvider);
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 420);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0 ||
            notification.metrics.axis != Axis.vertical) {
          return false;
        }
        if (notification is ScrollUpdateNotification) {
          _scheduleVisibleMeasurements(notification.metrics.pixels);
        }
        final dragging =
            (notification is ScrollStartNotification &&
                notification.dragDetails != null) ||
            (notification is ScrollUpdateNotification &&
                notification.dragDetails != null) ||
            (notification is UserScrollNotification &&
                notification.direction != ScrollDirection.idle);
        if (dragging) {
          _stopScrollMotion();
          _userScrolling = true;
          _userScrollIdleTimer?.cancel();
        } else if (notification is ScrollEndNotification && _userScrolling) {
          // Start the return-to-playback timeout only after the drag and its
          // momentum finish. A direction notification is not an idle event:
          // a long drag can keep that direction while controls fade in/out.
          _scheduleUserScrollReturn();
        }
        return false;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final inset = sistrum ? appLyricsContentInset : 24.0;
          final contentWidth = (constraints.maxWidth - inset * 2).clamp(
            0.0,
            double.infinity,
          );
          // Lay out at the existing lyric width, then fit the whole line to
          // the timeline. Scaling text, phrase gaps and supplements together
          // preserves wrapping instead of pushing extra words onto a new row.
          final layoutWidth = (constraints.maxWidth - 48).clamp(
            0.0,
            double.infinity,
          );
          final lyricScale = sistrum && layoutWidth > 0
              ? contentWidth / layoutWidth
              : 1.0;
          if (sistrum) {
            final previousExtents = _lineExtents;
            final previousScrollAnchor =
                previousExtents != null && _scroll.hasClients
                ? _rowAtScrollOffset(previousExtents, _scroll.offset)
                : 0;
            final focusAnchor = _focus < 0
                ? 0
                : _displayLayout.rowForLine[_focus];
            final previousScrollOffset =
                previousExtents?.offsetForRow(previousScrollAnchor) ?? 0;
            final previousFocusOffset =
                previousExtents?.offsetForRow(focusAnchor) ?? 0;
            _measureAppLines(context, layoutWidth);
            // Reuse text measurements; only interpolate row heights as the
            // supplements fade. Scrolling follows the same animation clock.
            final geometryKey = (
              _lineMeasurements,
              lyricScale,
              _revealFrom,
              _revealTo,
            );
            if (_extentGeometryKey != geometryKey) {
              _extentGeometryKey = geometryKey;
              _extentGeometry = _LyricExtentGeometry(
                _lineMeasurements,
                _displayLayout.lineOrder,
                _revealFrom,
                _revealTo,
                (index) => _lines[index].text.isEmpty ? 1.0 : lyricScale,
                (index) => _linePadding(index).vertical,
              );
            } else {
              for (final row in _changedMeasurementRows) {
                _extentGeometry!.updateRow(row, _lineMeasurements[row]);
              }
            }
            _changedMeasurementRows.clear();
            _lineExtents = _LyricExtentSnapshot(
              _extentGeometry!,
              visibility,
              Curves.easeInOutCubic.transform(_rowReveal.value),
            );
            _targetLineExtents = _LyricExtentSnapshot(
              _extentGeometry!,
              visibility,
              1,
            );
            if (previousExtents != null &&
                ((_layoutMeasurementRevision != _measurementRevision) ||
                    (_layoutVisibility != null &&
                        _layoutVisibility != visibility) ||
                    (_preserveRevealAnchor &&
                        previousExtents.progress != _lineExtents!.progress)) &&
                previousExtents.length == _lineExtents!.length &&
                _scroll.hasClients) {
              final preserveScroll =
                  _userScrolling ||
                  _layoutMeasurementRevision != _measurementRevision;
              final anchor = preserveScroll
                  ? previousScrollAnchor
                  : focusAnchor;
              final correction =
                  _lineExtents!.offsetForRow(anchor) -
                  (preserveScroll ? previousScrollOffset : previousFocusOffset);
              // Correct before the ListView lays out/paints. A post-frame
              // jump leaves every painted frame one animation step behind.
              if (correction != 0) _scroll.position.correctBy(correction);
            }
          }
          _layoutVisibility = visibility;
          _layoutMeasurementRevision = _measurementRevision;
          if (_viewportHeight != constraints.maxHeight) {
            _viewportHeight = constraints.maxHeight;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                unawaited(_maybeAutoScroll(_active, immediate: true));
              }
            });
          }
          final topPadding = sistrum
              ? _focusInset
              : syncedLyricsCenterPadding(
                  viewportDimension: constraints.maxHeight,
                  estimatedLineExtent:
                      _SyncedLyricsViewState._estimatedLyricExtent,
                );
          // Leave enough trailing space for the final line to reach the same
          // upper focus position as every other line.
          final bottomPadding = sistrum && _lineExtents!.isNotEmpty
              ? (constraints.maxHeight - _lineExtents!.last - topPadding).clamp(
                  topPadding,
                  double.infinity,
                )
              : topPadding;
          return ListView.builder(
            controller: _scroll,
            itemExtentBuilder: sistrum
                ? (index, _) => index < lines.length
                      ? _lineExtents![index]
                      : widget.credits!.heightFor(context, contentWidth)
                : null,
            padding: EdgeInsets.fromLTRB(
              inset,
              topPadding,
              inset,
              bottomPadding,
            ),
            itemCount: lines.length + (widget.credits == null ? 0 : 1),
            itemBuilder: (context, row) {
              if (row == lines.length) return widget.credits!;
              final index = _displayLayout.lineOrder[row];
              final line = lines[index];
              final leadIndex = _displayLayout.leadForLine[index];
              final textAlign = _lyricTextAlign(context, lines[leadIndex]);
              final lineDirection = lyricLineDirection(
                line.text,
                Directionality.of(context),
              );
              final reveal = rowVisibility[index];
              if (reveal == 0) return SizedBox.shrink(key: _lineKeys[index]);
              final isActive = _activeLines.contains(index);
              final isPast = index < active;

              final color = sistrum
                  ? Colors.white
                  : isActive
                  ? widget.colorScheme.onSurface
                  : isPast
                  ? widget.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                  : widget.colorScheme.onSurfaceVariant.withValues(alpha: 0.8);

              if (line.text.isEmpty) {
                return _revealRow(
                  index,
                  reveal,
                  textAlign,
                  Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: context.tokens.lyricsLinePaddingV,
                    ),
                    child: SizedBox(
                      height: 24,
                      child: Align(
                        alignment: sistrum
                            ? AlignmentDirectional.centerStart
                            : Alignment.center,
                        child:
                            isActive &&
                                _visible &&
                                (!loading || widget.seekPreview.value != null)
                            ? ValueListenableBuilder<Duration?>(
                                valueListenable: widget.seekPreview,
                                builder: (context, preview, _) =>
                                    LyricGapIndicator(
                                      key: ValueKey(line.time),
                                      start: line.time,
                                      end: line.end!,
                                      color: color,
                                      position: preview,
                                    ),
                              )
                            : null,
                      ),
                    ),
                  ),
                );
              }

              final timed =
                  isActive &&
                  (line.hasWordTiming || line.romanizationWords.isNotEmpty);
              Widget content;
              if (timed) {
                content = _WordHighlightedLyricLine(
                  line: line,
                  colorScheme: widget.colorScheme,
                  animate: _visible,
                  initialPosition: _activeTransitionPosition,
                  seekPreview: widget.seekPreview,
                  supplementVisibility: visibility,
                  pronunciationLayout: sistrum
                      ? _pronunciationLayouts[index]
                      : null,
                  textAlign: textAlign,
                );
              } else {
                content = Text(
                  line.text,
                  textAlign: textAlign,
                  // Focus changes paint scale, never font metrics or wrapping
                  // shared by the plain and word-timed line.
                  style: sistrum
                      ? _appLyricStyle(
                          context,
                          background: line.isBackground,
                        ).copyWith(color: color)
                      : (isActive
                                ? Theme.of(context).textTheme.headlineSmall
                                : Theme.of(context).textTheme.titleLarge)
                            ?.copyWith(
                              height: context.tokens.lyricsLineHeight,
                              fontSize: line.isBackground ? 18 : null,
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: color,
                            ),
                );
                content = _withLyricSupplements(
                  context,
                  line,
                  content,
                  color,
                  visibility: visibility,
                  pronunciationLayout: sistrum
                      ? _pronunciationLayouts[index]
                      : null,
                  textAlign: textAlign,
                );
              }
              content = AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 320),
                reverseDuration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: KeyedSubtree(
                  key: ValueKey(timed),
                  child: SizedBox(width: double.infinity, child: content),
                ),
              );
              if (sistrum) {
                final activeLead = active < 0 ? -1 : _focus;
                final distance = activeLead < 0
                    ? row + 1
                    : (_displayLayout.rowForLine[leadIndex] -
                              _displayLayout.rowForLine[activeLead])
                          .abs();
                // Nearby lines need visible defocus at the larger lyric size;
                // progressively soften lines further from the current one.
                final sigma = !blurLyrics || isActive || leadIndex == activeLead
                    ? 0.0
                    : active < 0
                    ? 4.8
                    : distance == 1
                    ? 2.4
                    : distance == 2
                    ? 3.6
                    : 4.8;
                content = TweenAnimationBuilder<double>(
                  tween: Tween(end: sigma),
                  duration: motion,
                  curve: Curves.easeInOutCubic,
                  child: RepaintBoundary(child: content),
                  builder: (context, value, child) => ImageFiltered(
                    enabled: value > 0,
                    imageFilter: ImageFilter.blur(sigmaX: value, sigmaY: value),
                    child: child,
                  ),
                );
                content = FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.topStart,
                  child: SizedBox(width: layoutWidth, child: content),
                );
              }

              content = LyricScrollMotion(
                progress: _scrollMotion,
                distance: _scrollMotionDistance,
                rowsAfterFocus: row - _scrollMotionFocus,
                enabled: !isActive,
                child: content,
              );
              return Directionality(
                textDirection: lineDirection,
                child: _revealRow(
                  index,
                  reveal,
                  textAlign,
                  Padding(
                    padding: _linePadding(index),
                    child: GestureDetector(
                      onTap: () => ref
                          .read(musicPlayerControllerProvider)
                          .seek(line.time),
                      onLongPress: widget.onLongPressLine == null
                          ? null
                          : () {
                              HapticFeedback.mediumImpact();
                              widget.onLongPressLine!(line);
                            },
                      child: AnimatedScale(
                        scale: isActive ? 1.0 : 0.96,
                        alignment: !sistrum
                            ? Alignment.center
                            : (textAlign == TextAlign.end
                                      ? AlignmentDirectional.centerEnd
                                      : AlignmentDirectional.centerStart)
                                  .resolve(lineDirection),
                        duration: motion,
                        curve: Curves.easeOutCubic,
                        child: AnimatedOpacity(
                          opacity: sistrum
                              ? (isActive || highContrast ? 1 : 0.48)
                              : (isActive ? 1.0 : (isPast ? 0.55 : 0.85)),
                          duration: motion,
                          curve: Curves.easeInOutCubic,
                          child: content,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
