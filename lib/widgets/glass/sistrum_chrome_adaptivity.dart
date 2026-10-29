import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:sistrum/navigation/shell_navigation.dart';

/// The shell bar's light/dark verdict, sampled from the page behind it.
///
/// Sampling is held at rest: the package sampler would otherwise keep reading
/// back the page while the mini player's progress renders frames. It runs
/// continuously only while a page scrolls, and takes single looks when a
/// scroll settles, artwork may have faded in, or the visible page changes.
class SistrumChromeAdaptivity {
  SistrumChromeAdaptivity() {
    ShellNavigationService.pageChanges.addListener(settled);
  }

  /// Published by the sampling area; null until the first look.
  final link = LiquidGlassAdaptivityLink();
  final controller = LiquidGlassAdaptivityController(enabled: false);
  Timer? _followUp;

  /// Covers artwork that finishes loading just after the first look.
  static const followUpDelay = Duration(milliseconds: 400);

  void scrollStarted() {
    _followUp?.cancel();
    controller.enable();
  }

  void settled() {
    controller.disable();
    controller.adaptOnce();
    _followUp?.cancel();
    _followUp = Timer(followUpDelay, controller.adaptOnce);
  }

  void dispose() {
    ShellNavigationService.pageChanges.removeListener(settled);
    _followUp?.cancel();
    controller.dispose();
    link.dispose();
  }
}

/// A page's explicit chrome brightness (the artist page) wins over the
/// sampled verdict; null keeps the app theme.
Brightness? sistrumChromeBrightness({
  required Brightness? pageOverride,
  required Brightness? sampled,
}) => pageOverride ?? sampled;

/// Hosts the shell's pages as the background of one package view whose only
/// job is to sample the strip behind the bottom bar. The bar itself is not in
/// that background, so it never judges its own glass.
///
/// With [enabled] false it is exactly [child]: no view, no sampler.
class SistrumChromeBackdrop extends StatefulWidget {
  const SistrumChromeBackdrop({
    super.key,
    required this.adaptivity,
    required this.enabled,
    required this.child,
  });

  final SistrumChromeAdaptivity adaptivity;
  final bool enabled;
  final Widget child;

  static const sampling = LiquidGlassAdaptiveSampling(frameLimit: 6);

  @override
  State<SistrumChromeBackdrop> createState() => _SistrumChromeBackdropState();
}

class _SistrumChromeBackdropState extends State<SistrumChromeBackdrop> {
  @override
  void initState() {
    super.initState();
    if (widget.enabled) _lookAfterFrame();
  }

  @override
  void didUpdateWidget(SistrumChromeBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) _lookAfterFrame();
  }

  void _lookAfterFrame() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && widget.enabled) widget.adaptivity.settled();
  });

  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      widget.adaptivity.scrollStarted();
    } else if (notification is ScrollEndNotification) {
      widget.adaptivity.settled();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    // With extendBody the page's bottom padding is the bar's full height.
    final footprint = math.max(MediaQuery.paddingOf(context).bottom, 1.0);
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: LiquidGlassView(
        // Only mounted where shader filters exist; no Skia capture pipeline.
        useImpellerBackdrop: true,
        // Page glass keeps its own backdrop reads.
        batch: false,
        realTimeCapture: false,
        adaptiveSampling: SistrumChromeBackdrop.sampling,
        backgroundWidget: widget.child,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: footprint,
                  child: LiquidGlassAdaptiveArea(
                    key: const ValueKey('sistrum-bar-adaptive-area'),
                    adaptivity: LiquidGlassAdaptivity(
                      link: widget.adaptivity.link,
                      controller: widget.adaptivity.controller,
                    ),
                    systemChrome: LiquidGlassSystemChrome.navigationBar,
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
