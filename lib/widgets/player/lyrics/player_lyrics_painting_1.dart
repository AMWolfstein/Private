part of 'player_lyrics.dart';

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
    final style = _appLyricStyle(context, background: widget.line.isBackground);
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
