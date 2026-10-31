part of 'player_lyrics.dart';

class _SweepingTimedLyricTextState extends State<_SweepingTimedLyricText> {
  TextPainter? _pendingPainter;
  TextPainter? _highlightedPainter;
  String? _cachedText;
  TextStyle? _cachedStyle;
  TextAlign? _cachedAlignment;
  TextDirection? _cachedDirection;
  TextScaler? _cachedScaler;
  Locale? _cachedLocale;
  Color? _cachedPendingColor;
  Color? _cachedHighlightedColor;
  List<String>? _cachedSegments;
  List<List<Rect>>? _cachedSegmentBoxes;
  double? _cachedMinWidth;
  double? _cachedMaxWidth;

  void _ensurePainters(
    String text,
    TextDirection textDirection,
    TextScaler textScaler,
    Locale? locale,
  ) {
    if (_cachedText == text &&
        _cachedStyle == widget.style &&
        _cachedAlignment == widget.textAlign &&
        _cachedDirection == textDirection &&
        _cachedScaler == textScaler &&
        _cachedLocale == locale &&
        _cachedPendingColor == widget.pendingColor &&
        _cachedHighlightedColor == widget.highlightedColor) {
      return;
    }

    _pendingPainter?.dispose();
    _highlightedPainter?.dispose();
    _cachedSegmentBoxes = null;
    _pendingPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: widget.style.copyWith(color: widget.pendingColor),
      ),
      textAlign: widget.textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
    );
    _highlightedPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: widget.style.copyWith(color: widget.highlightedColor),
      ),
      textAlign: widget.textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
    );
    _cachedText = text;
    _cachedStyle = widget.style;
    _cachedAlignment = widget.textAlign;
    _cachedDirection = textDirection;
    _cachedScaler = textScaler;
    _cachedLocale = locale;
    _cachedPendingColor = widget.pendingColor;
    _cachedHighlightedColor = widget.highlightedColor;
  }

  List<List<Rect>> _segmentBoxes(
    double minWidth,
    double maxWidth,
    bool rightToLeft,
  ) {
    if (_cachedSegmentBoxes != null &&
        _cachedMinWidth == minWidth &&
        _cachedMaxWidth == maxWidth &&
        listEquals(_cachedSegments, widget.segments)) {
      return _cachedSegmentBoxes!;
    }

    final segmentBoxes = <List<Rect>>[];
    var segmentOffset = 0;
    for (final segment in widget.segments) {
      final segmentEnd = segmentOffset + segment.length;
      // Select the whole timed word, keeping paragraph shaping and wrapping
      // intact. All of its text runs share the same vertical movement.
      final boxes = _highlightedPainter!
          .getBoxesForSelection(
            TextSelection(baseOffset: segmentOffset, extentOffset: segmentEnd),
            boxHeightStyle: BoxHeightStyle.max,
          )
          .map((box) => box.toRect())
          .toList();
      // Boxes run in reading order: right to left on an RTL line.
      boxes.sort((a, b) {
        final row = a.top.compareTo(b.top);
        if (row != 0) return row;
        return rightToLeft
            ? b.left.compareTo(a.left)
            : a.left.compareTo(b.left);
      });
      segmentBoxes.add(boxes);
      segmentOffset = segmentEnd;
    }
    // Snapshot contents: callers can rebuild equal lists or mutate boundaries
    // without changing the joined text. Timing is supplied separately below.
    _cachedSegments = List<String>.of(widget.segments);
    _cachedMinWidth = minWidth;
    _cachedMaxWidth = maxWidth;
    return _cachedSegmentBoxes = segmentBoxes;
  }

  @override
  void dispose() {
    _pendingPainter?.dispose();
    _highlightedPainter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);
    final text = widget.segments.join();
    _ensurePainters(text, textDirection, textScaler, locale);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : double.infinity;
        final minWidth = constraints.hasBoundedWidth ? maxWidth : 0.0;
        final pendingPainter = _pendingPainter!
          ..layout(minWidth: minWidth, maxWidth: maxWidth);
        final highlightedPainter = _highlightedPainter!
          ..layout(minWidth: minWidth, maxWidth: maxWidth);
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : pendingPainter.width;
        final height = pendingPainter.height;
        final rightToLeft = textDirection == TextDirection.rtl;
        final segmentBoxes = _segmentBoxes(minWidth, maxWidth, rightToLeft);

        return Semantics(
          label: widget.semanticsLabel,
          child: CustomPaint(
            size: Size(width, height),
            painter: _TimedLyricSweepPainter(
              segmentBoxes: segmentBoxes,
              starts: widget.starts,
              ends: widget.ends,
              currentPosition: widget.currentPosition,
              repaint: widget.repaint,
              pendingPainter: pendingPainter,
              highlightedPainter: highlightedPainter,
              highlightLift: widget.liftEnabled
                  ? (textScaler.scale(widget.style.fontSize ?? 24) * 0.05)
                        .clamp(0.0, 2.0)
                  : 0,
              glowSigma: widget.liftEnabled
                  ? textScaler.scale(widget.style.fontSize ?? 24) * 0.2
                  : 0,
              rightToLeft: rightToLeft,
            ),
          ),
        );
      },
    );
  }
}

class _TimedLyricSweepPainter extends CustomPainter {
  final List<List<Rect>> segmentBoxes;
  final List<Duration> starts;
  final List<Duration> ends;
  final Duration Function() currentPosition;
  final TextPainter pendingPainter;
  final TextPainter highlightedPainter;
  final double highlightLift;

  /// Blur radius of the glow behind held words; 0 disables it.
  final double glowSigma;

  /// The sweep starts at each word's right edge on an RTL line.
  final bool rightToLeft;

  _TimedLyricSweepPainter({
    required this.segmentBoxes,
    required this.starts,
    required this.ends,
    required this.currentPosition,
    required Listenable repaint,
    required this.pendingPainter,
    required this.highlightedPainter,
    required this.highlightLift,
    required this.glowSigma,
    required this.rightToLeft,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final pendingPaths = <double, Path>{};
    final completedPaths = <double, Path>{};
    final partialBoxes = <(Rect, double, double, double)>[];
    final glows = <(Path, double, double)>[];
    final position = currentPosition();
    for (var index = 0; index < segmentBoxes.length; index++) {
      final timed = index < starts.length && index < ends.length;
      final value = timed
          ? syncedLyricSegmentProgress(
              position: position,
              start: starts[index],
              end: ends[index],
            )
          : 0.0;
      final boxes = segmentBoxes[index];
      final width = boxes.fold<double>(0, (sum, box) => sum + box.width);
      final lift = highlightLift > 0 && timed
          ? highlightLift *
                syncedLyricSegmentLift(
                  position: position,
                  start: starts[index],
                  end: ends[index],
                )
          : 0.0;
      final glow = glowSigma > 0 && timed && value > 0
          ? syncedLyricSegmentGlow(
              position: position,
              start: starts[index],
              end: ends[index],
            )
          : 0.0;
      final glowPath = glow > 0.01 ? Path() : null;
      var consumed = 0.0;
      for (final box in boxes) {
        if (box.width <= 0) continue;
        if (highlightLift > 0) {
          pendingPaths.putIfAbsent(lift, Path.new).addRect(box);
        }
        // Keep the color sweep continuous across wrapping and font fallback,
        // independently of the movement shared by the whole word.
        final revealWidth = width * value - consumed;
        // A wide, soft leading edge reads as a smooth flow, not a wipe.
        final feather = ((highlightLift > 0 ? width : box.width) * 0.3).clamp(
          4.0,
          16.0,
        );
        // Only the sung part glows, so unsung letters never light up early.
        if (glowPath != null && revealWidth > 0) {
          final sungWidth = revealWidth.clamp(0.0, box.width);
          glowPath.addRect(
            rightToLeft
                ? Rect.fromLTRB(
                    box.right - sungWidth,
                    box.top,
                    box.right,
                    box.bottom,
                  )
                : Rect.fromLTRB(
                    box.left,
                    box.top,
                    box.left + sungWidth,
                    box.bottom,
                  ),
          );
        }
        if (value > 0 && revealWidth >= box.width) {
          completedPaths.putIfAbsent(lift, Path.new).addRect(box);
        } else if (value > 0 && revealWidth > -feather) {
          partialBoxes.add((box, revealWidth / box.width, lift, feather));
        }
        consumed += box.width;
      }
      if (glowPath != null) glows.add((glowPath, lift, glow));
    }

    // Move both colors together, so a raised highlight never leaves a dim
    // duplicate behind. Most words share the resting or completed position.
    if (highlightLift > 0) {
      for (final entry in pendingPaths.entries) {
        _paintLiftedText(canvas, pendingPainter, entry.value, entry.key);
      }
    } else {
      pendingPainter.paint(canvas, Offset.zero);
    }

    // A blurred copy of the sung letters behind them. Usually at most one
    // held word glows, so the extra layer stays cheap.
    for (final (clip, lift, glow) in glows) {
      final bounds = clip.getBounds().inflate(glowSigma * 3);
      canvas.save();
      canvas.translate(0, -lift);
      canvas.saveLayer(
        bounds,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, 0.55 * glow)
          ..imageFilter = ImageFilter.blur(
            sigmaX: glowSigma,
            sigmaY: glowSigma,
          ),
      );
      canvas.clipPath(clip, doAntiAlias: false);
      highlightedPainter.paint(canvas, Offset.zero);
      canvas.restore();
      canvas.restore();
    }
    for (final entry in completedPaths.entries) {
      _paintLiftedText(canvas, highlightedPainter, entry.value, entry.key);
    }

    for (final (box, value, lift, feather) in partialBoxes) {
      // Feather the leading edge so the highlight flows through each letter
      // while the word rises as a single unit.
      // The sung part is left of the boundary, or right of it on RTL.
      final boundary = rightToLeft
          ? box.right - box.width * value
          : box.left + box.width * value;
      final revealEdge = rightToLeft
          ? (boundary - feather).clamp(box.left, box.right)
          : (boundary + feather).clamp(box.left, box.right);
      final revealRect = rightToLeft
          ? Rect.fromLTRB(revealEdge, box.top, box.right, box.bottom)
          : Rect.fromLTRB(box.left, box.top, revealEdge, box.bottom);
      canvas.save();
      canvas.translate(0, -lift);
      canvas.clipRect(revealRect);
      canvas.saveLayer(revealRect, Paint());
      highlightedPainter.paint(canvas, Offset.zero);
      final mask = Paint()
        ..blendMode = BlendMode.dstIn
        ..shader =
            LinearGradient(
              colors: rightToLeft
                  ? const [Colors.transparent, Colors.white]
                  : const [Colors.white, Colors.transparent],
            ).createShader(
              rightToLeft
                  ? Rect.fromLTRB(
                      boundary - feather,
                      box.top,
                      boundary,
                      box.bottom,
                    )
                  : Rect.fromLTRB(
                      boundary,
                      box.top,
                      boundary + feather,
                      box.bottom,
                    ),
            );
      canvas.drawRect(revealRect, mask);
      canvas.restore();
      canvas.restore();
    }
  }

  void _paintLiftedText(
    Canvas canvas,
    TextPainter painter,
    Path clip,
    double lift,
  ) {
    canvas.save();
    canvas.translate(0, -lift);
    canvas.clipPath(clip, doAntiAlias: false);
    painter.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TimedLyricSweepPainter oldDelegate) {
    return oldDelegate.segmentBoxes != segmentBoxes ||
        oldDelegate.starts != starts ||
        oldDelegate.ends != ends ||
        oldDelegate.currentPosition != currentPosition ||
        oldDelegate.highlightLift != highlightLift ||
        oldDelegate.glowSigma != glowSigma ||
        oldDelegate.rightToLeft != rightToLeft ||
        oldDelegate.pendingPainter != pendingPainter ||
        oldDelegate.highlightedPainter != highlightedPainter;
  }
}
