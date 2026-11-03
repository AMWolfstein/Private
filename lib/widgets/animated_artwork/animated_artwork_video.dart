import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:video_player/video_player.dart';

/// A looping, silent video cover over its static [fallback].
///
/// - The static cover stays until the first video frame is on screen, so
///   there is no black flash, and it stays if the video cannot start.
/// - The video never takes audio focus or changes music volume: it is muted
///   and created with `mixWithOthers`, so native music playback is untouched.
/// - It plays only while the route is uncovered and the app is resumed, and
///   only when the glass/performance policy and reduced motion allow it.
///   Otherwise it is paused, and the decoder is released when disposed.
class AnimatedArtworkVideo extends ConsumerStatefulWidget {
  const AnimatedArtworkVideo({
    super.key,
    required this.fallback,
    this.file,
    this.networkUrl,
    this.active = true,
    this.fit = BoxFit.cover,
  }) : assert(
         (file == null) != (networkUrl == null),
         'Pass exactly one of file or networkUrl',
       );

  /// A saved video in the app's own storage.
  final File? file;

  /// A catalog preview, used only by the Find animated artwork sheet.
  final String? networkUrl;

  /// The static artwork shown under or instead of the video.
  final Widget fallback;

  /// Lyrics and other pause-the-motion states pass false here.
  final bool active;
  final BoxFit fit;

  @override
  ConsumerState<AnimatedArtworkVideo> createState() =>
      _AnimatedArtworkVideoState();
}

class _AnimatedArtworkVideoState extends ConsumerState<AnimatedArtworkVideo>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;

  /// Bumped on every load, so a late initialization cannot publish a player
  /// for a file that is no longer shown.
  int _generation = 0;
  bool _firstFrame = false;
  bool _failed = false;
  bool _resumed = true;
  bool _covered = false;
  bool _reduceMotion = false;
  bool _tickerEnabled = true;
  ModalRoute<Object?>? _route;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reset();
    _load();
  }

  /// Shows the static artwork at once, then loads the new file.
  void _reset() {
    ++_generation;
    final previous = _controller;
    _controller = null;
    previous?.dispose();
    _firstFrame = false;
    _failed = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    final route = ModalRoute.of(context);
    if (!identical(route, _route)) {
      _route?.secondaryAnimation?.removeListener(_onCover);
      _route = route;
      route?.secondaryAnimation?.addListener(_onCover);
      _covered = (route?.secondaryAnimation?.value ?? 0) > 0;
    }
    _sync();
  }

  @override
  void didUpdateWidget(AnimatedArtworkVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file?.path != widget.file?.path ||
        oldWidget.networkUrl != widget.networkUrl) {
      setState(_reset);
      _load();
    } else {
      _sync();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _route?.secondaryAnimation?.removeListener(_onCover);
    _generation++;
    final controller = _controller;
    _controller = null;
    controller?.dispose();
    super.dispose();
  }

  void _onCover() {
    final covered = (_route?.secondaryAnimation?.value ?? 0) > 0;
    if (covered != _covered) {
      _covered = covered;
      _sync();
    }
  }

  bool get _shouldPlay =>
      widget.active &&
      _resumed &&
      !_covered &&
      !_reduceMotion &&
      _tickerEnabled &&
      ref.read(appGlassLevelProvider) != AppGlassLevel.flat;

  void _sync() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_shouldPlay) {
      if (!controller.value.isPlaying) controller.play();
    } else if (controller.value.isPlaying) {
      controller.pause();
    }
  }

  Future<void> _load() async {
    final generation = _generation;

    final options = VideoPlayerOptions(mixWithOthers: true);
    final file = widget.file;
    final url = widget.networkUrl;
    final controller = file != null
        ? VideoPlayerController.file(file, videoPlayerOptions: options)
        : VideoPlayerController.networkUrl(
            Uri.parse(url!),
            videoPlayerOptions: options,
          );
    try {
      await controller.initialize();
    } on Object {
      await controller.dispose();
      if (generation == _generation && mounted) {
        setState(() => _failed = true);
      }
      return;
    }
    if (generation != _generation || !mounted) {
      await controller.dispose();
      return;
    }
    await controller.setLooping(true);
    await controller.setVolume(0);
    controller.addListener(_onPlayerValue);
    _controller = controller;
    setState(() {});
    _sync();
  }

  void _onPlayerValue() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    if (controller.value.hasError && !_failed) {
      setState(() {
        _failed = true;
        _controller = null;
      });
      controller.dispose();
      return;
    }
    // The first frame is drawn once the position moves off zero. Until then
    // the static artwork shows, so the texture's black start never does.
    final drawn = controller.value.position > Duration.zero;
    if (drawn != _firstFrame) setState(() => _firstFrame = drawn);
  }

  @override
  Widget build(BuildContext context) {
    // Watching the policy keeps the video in step with the glass setting.
    ref.watch(appGlassLevelProvider);
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.fallback,
        if (ready && !_failed)
          AnimatedOpacity(
            opacity: _firstFrame ? 1 : 0,
            duration: const Duration(milliseconds: 240),
            child: ClipRect(
              child: FittedBox(
                fit: widget.fit,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
