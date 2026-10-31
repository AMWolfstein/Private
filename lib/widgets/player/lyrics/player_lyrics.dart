import 'dart:async';
import 'dart:collection';
import 'dart:ui' show BoxHeightStyle, ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show OverflowBoxFit, RenderAbstractViewport, ScrollDirection;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/core/theme/app_tokens.dart';
import 'package:sistrum/utils/lyrics/lyrics_parser.dart';
import 'package:sistrum/utils/lyrics/lyric_models.dart';
import 'package:sistrum/utils/lyrics/synced_lyrics_scroll.dart';
import 'package:sistrum/widgets/lyrics/aligned_lyric_pronunciation.dart';
import 'package:sistrum/widgets/lyrics/lyric_gap_indicator.dart';
import 'package:sistrum/widgets/lyrics/lyric_scroll_motion.dart';
import 'package:sistrum/utils/lyrics/lyric_direction.dart';
import 'package:sistrum/widgets/lyrics/lyric_supplement_transition.dart';
import 'package:sistrum/widgets/lyrics/lyrics_text_scale.dart';
import 'package:sistrum/widgets/player/controls/app_player_slider.dart';

part 'player_lyrics_members_1.dart';
part 'player_lyrics_members_2.dart';
part 'player_lyrics_members_3.dart';
part 'player_lyrics_members_4.dart';

part 'player_lyrics_support_1.dart';
part 'player_lyrics_overrides_1.dart';
part 'player_lyrics_painting_1.dart';
part 'player_lyrics_painting_2.dart';
part 'player_lyrics_painting_3.dart';
part 'player_lyrics_layout_1.dart';

const _appLyricFontSize = 34.0;
const appLyricsContentInset = 28.0 + AppPlayerSlider.horizontalInset;

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

  // The header stays fixed when controls collapse. Anchor lyrics to it, not
  // to a fraction of the growing viewport, including during the transition.

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
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _didChangeAppLifecycleStateImpl(state);

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

  void _rebuild(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) => _buildImpl(context);
}

class LyricsCredits extends StatelessWidget {
  const LyricsCredits({super.key, this.writers, this.provider});

  final String? writers;
  final String? provider;

  String _text(BuildContext context) => [
    if (writers != null) context.l10n.nowPlayingWrittenBy(writers!),
    if (provider != null) context.l10n.nowPlayingLyricsSource(provider!),
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

// Merged over the ambient text style, as a Text widget would, so measured,
// plain and word-timed lines share the same metrics and wrapping.

/// Inserts empty, bounded rows for instrumental countdowns in the player.
/// Unmarked gaps in plain LRC cannot be distinguished from held vocals: only
/// use explicit empty timestamps or known line/word ends, never an estimate.
List<LyricLine> lyricsTimelineWithGaps(List<LyricLine> lines) {
  const minimumGap = Duration(seconds: 3);
  final timeline = <LyricLine>[];
  Duration? gapStart;
  Duration? latestVocalEnd;

  for (final line in lines) {
    if (line.text.trim().isEmpty) {
      gapStart ??= line.time;
      continue;
    }

    var start = timeline.isEmpty ? Duration.zero : gapStart;
    // A second vocal line may overlap a previous, longer one.
    if (start != null && latestVocalEnd != null && start < latestVocalEnd) {
      start = latestVocalEnd;
    }
    if (start != null && line.time - start >= minimumGap) {
      timeline.add(LyricLine(time: start, end: line.time, text: ''));
    }
    timeline.add(line);

    final lastWord = line.words.lastOrNull;
    var end = line.end;
    if (lastWord != null) {
      if (lastWord.end != null && (end == null || lastWord.end! > end)) {
        end = lastWord.end;
      }
      if (end != null && end < lastWord.time) end = null;
    }
    if (end != null && end < line.time) end = null;
    gapStart = end;
    if (end != null && (latestVocalEnd == null || end > latestVocalEnd)) {
      latestVocalEnd = end;
    }
  }
  // No following vocal means no countdown: trailing blank timestamps are
  // intentionally omitted, and credits stay after the last sung line.
  return List.unmodifiable(timeline);
}

/// Gives every word-timed line a known end for the player. Enhanced LRC often
/// omits the closing timestamp after the final word, which used to stop its
/// sweep after a fixed moment while the word was still being held.
///
/// A following line within [nearGap] receives the remaining time, so the last
/// word keeps sweeping slowly into it. A distant line usually follows a break:
/// the word then ends after a duration derived from the line's own pace.
/// Apply after [lyricsTimelineWithGaps]; countdown rows never use estimates.
List<LyricLine> lyricsWithDisplayEnds(
  List<LyricLine> timeline, {
  Duration nearGap = const Duration(seconds: 4),
}) {
  final result = <LyricLine>[];
  for (var i = 0; i < timeline.length; i++) {
    final line = timeline[i];
    final last = line.words.lastOrNull;
    if (line.text.isEmpty || last == null) {
      result.add(line);
      continue;
    }
    var end = line.end;
    if (last.end != null && (end == null || last.end! > end)) end = last.end;
    var words = line.words;
    if (last.end == null || last.end! <= last.time) {
      // An explicit line end still bounds an untimed final word.
      final estimate = end != null && end > last.time
          ? end
          : _estimatedFinalWordEnd(
              line.words,
              _nextBoundary(timeline, i),
              nearGap,
            );
      words = [
        ...line.words.take(line.words.length - 1),
        LyricWord(time: last.time, end: estimate, text: last.text),
      ];
      if (end == null || end < estimate) end = estimate;
    }
    if (end == line.end && identical(words, line.words)) {
      result.add(line);
      continue;
    }
    result.add(
      LyricLine(
        time: line.time,
        end: end,
        text: line.text,
        words: words,
        romanization: line.romanization,
        romanizationWords: line.romanizationWords,
        translation: line.translation,
        voice: line.voice,
        isBackground: line.isBackground,
        vocalGroup: line.vocalGroup,
      ),
    );
  }
  return List.unmodifiable(result);
}
