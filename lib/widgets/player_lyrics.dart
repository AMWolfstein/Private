import 'package:flutter/services.dart' show HapticFeedback;
import 'dart:async';
import 'dart:collection';
import 'dart:ui' show BoxHeightStyle, ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/rendering.dart'
    show OverflowBoxFit, RenderAbstractViewport, ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/theme/app_tokens.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/utils/lyrics_parser.dart';
import 'package:sistrum/utils/lyrics_timeline.dart';
import 'package:sistrum/utils/lyric_text_direction.dart';
import 'package:sistrum/utils/synced_lyrics_scroll.dart';
import 'package:sistrum/widgets/aligned_lyric_pronunciation.dart';
import 'package:sistrum/widgets/lyric_supplement_transition.dart';
import 'package:sistrum/widgets/lyric_scroll_motion.dart';
import 'package:sistrum/widgets/lyric_gap_indicator.dart';
import 'package:sistrum/widgets/sistrum_player_slider.dart';
import 'package:sistrum/widgets/lyrics_text_scale.dart';

const _sistrumLyricFontSize = 34.0;
const sistrumLyricsContentInset = 28.0 + SistrumPlayerSlider.horizontalInset;

/// How much of the lyrics area's bottom the player's controls cover. The
/// Sistrum phone player lays lyrics out under its controls so they can grow
/// when the controls hide; content that is not a scrolling lyric list keeps
/// clear of this part.
class LyricsCoveredBottom extends InheritedWidget {
  const LyricsCoveredBottom({
    super.key,
    required this.height,
    required super.child,
  });

  final double height;

  static double of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<LyricsCoveredBottom>()
          ?.height ??
      0;

  @override
  bool updateShouldNotify(LyricsCoveredBottom oldWidget) =>
      height != oldWidget.height;
}

class SyncedLyricsView extends ConsumerStatefulWidget {
  final ParsedLyrics lyrics;
  final ValueListenable<Duration?> seekPreview;
  final LyricsCredits? credits;
  final ColorScheme colorScheme;
  final bool isActive;
  final bool showPronunciation;
  final bool showTranslation;
  final ValueChanged<LyricLine>? onLongPressLine;

  const SyncedLyricsView({
    super.key,
    required this.lyrics,
    required this.seekPreview,
    this.credits,
    required this.colorScheme,
    required this.isActive,
    required this.showPronunciation,
    required this.showTranslation,
    this.onLongPressLine,
  });

  @override
  ConsumerState<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends ConsumerState<SyncedLyricsView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final ScrollController _scroll = ScrollController();
  ProviderSubscription<Duration>? _positionSubscription;
  ProviderSubscription<bool>? _playingSubscription;
  ProviderSubscription<bool>? _loadingSubscription;
  Timer? _lineBoundaryTimer;
  Timer? _userScrollIdleTimer;
  late List<LyricLine> _lines;
  late LyricTimelineIndex _timeline;
  late LyricDisplayLayout _displayLayout;
  late List<GlobalKey> _lineKeys;
  int _active = -1;
  Set<int> _activeLines = {};

  /// The line the view scrolls to; see [_focusFor].
  int _focus = -1;
  Duration _activeTransitionPosition = Duration.zero;
  bool _playing = false;
  bool _loading = false;
  bool _hasStarted = false;
  bool _userScrolling = false;
  bool _tickerEnabled = true;
  // An inactive app is still on screen: under the notification shade, a
  // system overlay or the other half of split screen.
  bool get _visible =>
      widget.isActive &&
      _tickerEnabled &&
      switch (WidgetsBinding.instance.lifecycleState) {
        null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
        _ => false,
      };
  static const double _estimatedLyricExtent = 64;
  _LyricExtentSnapshot? _lineExtents;
  List<(double, double, double)> _lineMeasurements = [];
  List<LyricPronunciationLayout?> _pronunciationLayouts = [];
  Object? _lineLayoutKey;
  final Set<int> _unmeasuredRows = {};
  final Set<int> _changedMeasurementRows = {};
  TextPainter? _measurementPainter;
  void Function(int)? _measureRow;
  Timer? _measurementTimer;
  int _measurementRevision = 0;
  int _layoutMeasurementRevision = 0;
  bool _measurementFramePending = false;
  double? _viewportHeight;
  Offset? _layoutVisibility;
  late final AnimationController _rowReveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..addListener(_revealTick);
  List<double> _revealFrom = [];
  List<double> _revealTo = [];
  _LyricExtentSnapshot? _targetLineExtents;
  _LyricExtentGeometry? _extentGeometry;
  Object? _extentGeometryKey;
  bool _preserveRevealAnchor = false;
  late final AnimationController _scrollMotion = AnimationController(
    vsync: this,
    duration: LyricScrollMotion.duration,
    value: 1,
  );
  double _scrollMotionDistance = 0;
  int _scrollMotionFocus = 0;

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
    setState(() {
      _scrollMotionDistance = distance;
      _scrollMotionFocus = row;
    });
    _scrollMotion.forward(from: 0);
  }

  void _revealTick() {
    if (mounted) setState(() {});
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

  // The header stays fixed when controls collapse. Anchor lyrics to it, not
  // to a fraction of the growing viewport, including during the transition.
  double get _focusInset =>
      (MediaQuery.sizeOf(context).height * 0.06).clamp(16.0, 48.0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resetLineKeys();
    widget.seekPreview.addListener(_previewChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Appearance can rebuild when transport controls fade (for example with
    // custom glass clarity). Keep the existing playback subscription and the
    // user's scroll ownership; only new lyrics/page activation should reset it.
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    if ((_positionSubscription != null) != _visible) {
      _syncPositionSubscription(resetUserScroll: false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A change that keeps the view on screen leaves the lyrics running.
    if ((_positionSubscription != null) != _visible) {
      _syncPositionSubscription(resetUserScroll: false);
    }
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant SyncedLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seekPreview != widget.seekPreview) {
      oldWidget.seekPreview.removeListener(_previewChanged);
      widget.seekPreview.addListener(_previewChanged);
    }
    if (oldWidget.lyrics != widget.lyrics) {
      _resetLineKeys();
    }
    if (oldWidget.showPronunciation != widget.showPronunciation ||
        oldWidget.showTranslation != widget.showTranslation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_userScrolling && _scroll.hasClients) {
          // Cancel a pending line-scroll once, then let layout preserve the
          // current anchor throughout the supplement animation.
          _scroll.jumpTo(_scroll.offset);
        }
      });
    }
    if (oldWidget.isActive != widget.isActive ||
        oldWidget.lyrics != widget.lyrics) {
      _syncPositionSubscription();
    }
  }

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
    setState(() {
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.seekPreview.removeListener(_previewChanged);
    _positionSubscription?.close();
    _playingSubscription?.close();
    _loadingSubscription?.close();
    _lineBoundaryTimer?.cancel();
    _userScrollIdleTimer?.cancel();
    _measurementTimer?.cancel();
    _measurementPainter?.dispose();
    _scroll.dispose();
    _rowReveal.dispose();
    _scrollMotion.dispose();
    super.dispose();
  }

  void _measureSistrumLines(BuildContext context, double width) {
    final style = _sistrumLyricStyle(context);
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
      _estimatedLyricExtent,
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
        style: _sistrumLyricStyle(context, background: line.isBackground),
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
            primaryStyle: _sistrumLyricStyle(
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
      setState(() {});
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
      if (mounted && _visible) setState(() {});
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
      estimatedLineExtent: _estimatedLyricExtent,
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

  @override
  Widget build(BuildContext context) => LyricsTextScale(
    child: TweenAnimationBuilder<Offset>(
      tween: Tween(
        end: Offset(
          widget.showPronunciation ? 1 : 0,
          widget.showTranslation ? 1 : 0,
        ),
      ),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
      builder: (context, visibility, _) => _buildLyrics(context, visibility),
    ),
  );

  Widget _buildLyrics(BuildContext context, Offset visibility) {
    final lines = _lines;
    final active = _active;
    final rowVisibility = _rowVisibility;
    final loading = _visible
        ? ref.watch(playbackLoadingProvider)
        : ref.read(playbackLoadingProvider);
    final sistrum = context.isSistrum;
    final highContrast = MediaQuery.highContrastOf(context);
    final blurLyrics =
        !highContrast &&
        // Every defocused line is filtered again on each playback frame.
        ref.watch(sistrumLiquidGlassProvider);
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
          final inset = sistrum ? sistrumLyricsContentInset : 24.0;
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
            _measureSistrumLines(context, layoutWidth);
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
                  estimatedLineExtent: _estimatedLyricExtent,
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
                      ? _sistrumLyricStyle(
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

class LyricsCredits extends StatelessWidget {
  const LyricsCredits({super.key, this.writers, this.provider});

  final String? writers;
  final String? provider;

  String _text(BuildContext context) => [
    if (writers != null) context.l10n.nowPlayingWrittenBy(writers!),
    if (provider != null) context.l10n.nowPlayingLyricsProvider(provider!),
  ].join('\n');

  TextStyle _style(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.48),
      );

  double heightFor(BuildContext context, double width) {
    final painter = TextPainter(
      text: TextSpan(text: _text(context), style: _style(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width.clamp(0, double.infinity));
    final height = painter.height + 32;
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(_text(context), style: _style(context)),
  );
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

// Merged over the ambient text style, as a Text widget would, so measured,
// plain and word-timed lines share the same metrics and wrapping.
TextStyle _sistrumLyricStyle(BuildContext context, {bool background = false}) =>
    DefaultTextStyle.of(context).style.merge(
      (Theme.of(context).textTheme.headlineSmall ?? const TextStyle()).copyWith(
        fontSize: _sistrumLyricFontSize * (background ? 0.68 : 1),
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
  final primaryStyle = _sistrumLyricStyle(
    context,
    background: line.isBackground,
  );
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

class _WordHighlightedLyricLineState
    extends ConsumerState<_WordHighlightedLyricLine>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _animationClock;
  final Stopwatch _elapsedClock = Stopwatch();
  ProviderSubscription<Duration>? _positionSubscription;
  ProviderSubscription<bool>? _playingSubscription;
  ProviderSubscription<bool>? _loadingSubscription;

  late Duration _anchorPosition;
  Duration _anchorElapsed = Duration.zero;
  bool _playing = false;
  bool _loading = false;
  bool _tickerEnabled = true;
  bool _hasSubscribed = false;
  Duration _visualEnd = Duration.zero;

  // An inactive app is still on screen, as in [SyncedLyricsView]: the sweep
  // keeps pace with the lines.
  bool get _visible =>
      widget.animate &&
      _tickerEnabled &&
      switch (WidgetsBinding.instance.lifecycleState) {
        null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
        _ => false,
      };

  bool get _advancing =>
      _visible && _playing && !_loading && widget.seekPreview.value == null;

  bool get _shouldAnimate => _advancing && _currentPosition() < _visualEnd;

  Duration _positionAt({required bool advance}) {
    return interpolatedSyncedLyricsPosition(
      anchorPosition: _anchorPosition,
      elapsedSinceAnchor: _elapsedClock.elapsed - _anchorElapsed,
      isPlaying: advance,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _elapsedClock.start();
    _anchorElapsed = _elapsedClock.elapsed;
    _anchorPosition = widget.initialPosition;
    _playing = ref.read(playbackPlayingProvider);
    _loading = ref.read(playbackLoadingProvider);
    _animationClock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_animationTick);
    widget.seekPreview.addListener(_previewChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _updateVisualEnd();
    _syncSubscriptions();
  }

  void _syncSubscriptions() {
    if (!_visible) {
      _positionSubscription?.close();
      _playingSubscription?.close();
      _loadingSubscription?.close();
      _positionSubscription = null;
      _playingSubscription = null;
      _loadingSubscription = null;
      _animationClock.stop();
      return;
    }
    if (_positionSubscription != null) {
      _syncAnimationClock();
      return;
    }
    _playing = ref.read(playbackPlayingProvider);
    _loading = ref.read(playbackLoadingProvider);
    if (_hasSubscribed) {
      _anchorAt(widget.seekPreview.value ?? ref.read(playbackPositionProvider));
    }
    _hasSubscribed = true;
    _positionSubscription = ref.listenManual<Duration>(
      playbackPositionProvider,
      (previous, next) => _updateReportedPosition(next),
    );
    _playingSubscription = ref.listenManual<bool>(
      playbackPlayingProvider,
      (previous, next) => _updateTransportState(playing: next),
    );
    _loadingSubscription = ref.listenManual<bool>(
      playbackLoadingProvider,
      (previous, next) => _updateTransportState(loading: next),
    );
    _syncAnimationClock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _syncSubscriptions();
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _WordHighlightedLyricLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seekPreview != widget.seekPreview) {
      oldWidget.seekPreview.removeListener(_previewChanged);
      widget.seekPreview.addListener(_previewChanged);
      _previewChanged();
    }
    if (oldWidget.line != widget.line ||
        oldWidget.initialPosition != widget.initialPosition) {
      _anchorAt(widget.initialPosition);
      _updateVisualEnd();
      _syncAnimationClock();
    }
    if (oldWidget.animate != widget.animate) {
      _syncSubscriptions();
    }
  }

  Duration _currentPosition() =>
      widget.seekPreview.value ?? _positionAt(advance: _advancing);

  void _previewChanged() {
    if (!mounted || !_visible) return;
    _anchorAt(widget.seekPreview.value ?? ref.read(playbackPositionProvider));
    _syncAnimationClock();
    setState(() {});
  }

  void _anchorAt(Duration position) {
    _anchorPosition = position;
    _anchorElapsed = _elapsedClock.elapsed;
  }

  void _updateReportedPosition(Duration position) {
    if (!mounted || widget.seekPreview.value != null) return;
    final predicted = _currentPosition();
    _anchorAt(
      _advancing
          ? reconcileSyncedLyricsPosition(
              predictedPosition: predicted,
              reportedPosition: position,
            )
          : position,
    );
    _syncAnimationClock();
    // A held line stays visible through an instrumental/outro. Once every
    // envelope has settled, later position reports cannot change its pixels.
    if (!_animationClock.isAnimating &&
        (predicted < _visualEnd || _currentPosition() < _visualEnd)) {
      setState(() {});
    }
  }

  void _updateTransportState({bool? playing, bool? loading}) {
    if (!mounted) return;
    final position = _currentPosition();
    if (playing != null) _playing = playing;
    if (loading != null) _loading = loading;
    _anchorAt(
      widget.seekPreview.value ??
          (_advancing ? position : ref.read(playbackPositionProvider)),
    );
    _syncAnimationClock();
    setState(() {});
  }

  void _syncAnimationClock() {
    if (_shouldAnimate) {
      if (!_animationClock.isAnimating) {
        _animationClock.repeat();
      }
    } else {
      _animationClock.stop();
    }
  }

  void _animationTick() {
    if (_currentPosition() >= _visualEnd) _animationClock.stop();
  }

  void _updateVisualEnd() {
    final decorativeMotion = !MediaQuery.disableAnimationsOf(context);
    var end = Duration.zero;
    for (final words in [widget.line.words, widget.line.romanizationWords]) {
      for (var index = 0; index < words.length; index++) {
        var wordEnd = _segmentEnd(words, index);
        if (decorativeMotion) {
          // Decorative envelopes may finish after the color sweep.
          final liftEnd = words[index].time + const Duration(milliseconds: 540);
          final held = (wordEnd - words[index].time).inMilliseconds > 900;
          if (held) wordEnd += const Duration(milliseconds: 500);
          if (liftEnd > wordEnd) wordEnd = liftEnd;
        }
        if (wordEnd > end) end = wordEnd;
      }
    }
    _visualEnd = end;
  }

  Duration _segmentEnd(List<LyricWord> words, int index) {
    final word = words[index];
    final start = word.time;
    if (word.end != null && word.end! >= start) return word.end!;
    if (index + 1 < words.length) {
      final next = words[index + 1].time;
      if (next > start) return next;
    }
    final lineEnd = widget.line.end;
    if (lineEnd != null && lineEnd > start) return lineEnd;
    return start + const Duration(milliseconds: 650);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.seekPreview.removeListener(_previewChanged);
    _positionSubscription?.close();
    _playingSubscription?.close();
    _loadingSubscription?.close();
    _animationClock.dispose();
    _elapsedClock.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _sistrumLyricStyle(
      context,
      background: widget.line.isBackground,
    );
    final primary = widget.line.hasWordTiming
        ? _buildTimedText(widget.line.text, widget.line.words, style)
        : Text(
            widget.line.text,
            textAlign: widget.textAlign,
            style: style.copyWith(color: widget.colorScheme.onSurface),
          );
    // Both scripts share this state's position interpolation and animation
    // clock, including pause, seek and track changes.
    return _withLyricSupplements(
      context,
      widget.line,
      primary,
      widget.colorScheme.onSurface,
      timedText: _buildTimedText,
      timedSupplementText: (text, words, style) =>
          _buildTimedText(text, words, style, lift: false),
      visibility: widget.supplementVisibility,
      pronunciationLayout: widget.pronunciationLayout,
      textAlign: widget.textAlign,
    );
  }

  Widget _buildTimedText(
    String text,
    List<LyricWord> words,
    TextStyle style, {
    bool lift = true,
  }) {
    final highlightedColor = widget.colorScheme.onSurface;

    final pendingColor = Colors.white.withValues(alpha: 0.4);
    return _SweepingTimedLyricText(
      segments: [for (final word in words) word.text],
      starts: [for (final word in words) word.time],
      ends: [
        for (var index = 0; index < words.length; index++)
          _segmentEnd(words, index),
      ],
      currentPosition: _currentPosition,
      repaint: _animationClock,
      style: style,
      textAlign: widget.textAlign,
      pendingColor: pendingColor,
      highlightedColor: highlightedColor,
      semanticsLabel: text,
      liftEnabled: lift && !MediaQuery.disableAnimationsOf(context),
    );
  }
}

class _SweepingTimedLyricText extends StatefulWidget {
  final List<String> segments;
  final List<Duration> starts;
  final List<Duration> ends;
  final Duration Function() currentPosition;
  final Listenable repaint;
  final TextStyle style;
  final TextAlign textAlign;
  final Color pendingColor;
  final Color highlightedColor;
  final String semanticsLabel;
  final bool liftEnabled;

  const _SweepingTimedLyricText({
    required this.segments,
    required this.starts,
    required this.ends,
    required this.currentPosition,
    required this.repaint,
    required this.style,
    required this.textAlign,
    required this.pendingColor,
    required this.highlightedColor,
    required this.semanticsLabel,
    required this.liftEnabled,
  });

  @override
  State<_SweepingTimedLyricText> createState() =>
      _SweepingTimedLyricTextState();
}

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

  List<List<Rect>> _segmentBoxes(double minWidth, double maxWidth) {
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
      boxes.sort((a, b) {
        final row = a.top.compareTo(b.top);
        return row == 0 ? a.left.compareTo(b.left) : row;
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
        final segmentBoxes = _segmentBoxes(minWidth, maxWidth);

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
          glowPath.addRect(
            Rect.fromLTRB(
              box.left,
              box.top,
              box.left + revealWidth.clamp(0.0, box.width),
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
      final boundary = box.left + box.width * value;
      final revealRight = (boundary + feather).clamp(box.left, box.right);
      final revealRect = Rect.fromLTRB(
        box.left,
        box.top,
        revealRight,
        box.bottom,
      );
      canvas.save();
      canvas.translate(0, -lift);
      canvas.clipRect(revealRect);
      canvas.saveLayer(revealRect, Paint());
      highlightedPainter.paint(canvas, Offset.zero);
      final mask = Paint()
        ..blendMode = BlendMode.dstIn
        ..shader =
            LinearGradient(
              colors: const [Colors.white, Colors.transparent],
            ).createShader(
              Rect.fromLTRB(boundary, box.top, boundary + feather, box.bottom),
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
        oldDelegate.pendingPainter != pendingPainter ||
        oldDelegate.highlightedPainter != highlightedPainter;
  }
}
