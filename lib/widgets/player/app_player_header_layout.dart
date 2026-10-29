import 'package:flutter/material.dart';
import 'package:sistrum/widgets/player/player_lyrics.dart';

const kAppPlayerContentInset = appLyricsContentInset;
const kAppPlayerHeaderButtonSize = 48.0;
const kAppPlayerCompactIconSize = 28.0;

enum AppPlayerHeaderSlot { stage, header, controls, lyricsOptions }

/// Keep one live header throughout the cover/lyrics/queue transition. Measuring
/// it at its current width also accommodates accessibility text sizes without
/// moving the transport controls below this layout.
class AppPlayerHeaderLayout extends MultiChildLayoutDelegate {
  AppPlayerHeaderLayout({
    required this.progress,
    required this.compactHeight,
    required this.compactLeft,
    required this.expandLyrics,
  });

  final double progress;
  final double compactHeight;
  final double compactLeft;
  final bool expandLyrics;

  @override
  void performLayout(Size size) {
    final controls = layoutChild(
      AppPlayerHeaderSlot.controls,
      BoxConstraints.tightFor(width: size.width),
    );
    final contentHeight = (size.height - controls.height).clamp(
      0.0,
      size.height,
    );
    positionChild(AppPlayerHeaderSlot.controls, Offset(0, contentHeight));
    final left = 28 + (compactLeft - 28) * progress;
    // Align the visible ellipsis with the timeline while leaving its touch
    // target wider than the glyph and interpolating the same live header.
    const compactRight =
        kAppPlayerContentInset -
        (kAppPlayerHeaderButtonSize - kAppPlayerCompactIconSize) / 2;
    final right = 28 + (compactRight - 28) * progress;
    final header = layoutChild(
      AppPlayerHeaderSlot.header,
      BoxConstraints(
        minWidth: size.width - left - right,
        maxWidth: size.width - left - right,
        minHeight: compactHeight * progress,
      ),
    );
    final stageHeight = (contentHeight - (header.height + 20) * (1 - progress))
        .clamp(0.0, contentHeight);
    layoutChild(
      AppPlayerHeaderSlot.stage,
      // Lyrics always extend behind controls. The minimum height marks their
      // unobscured area for the paint mask; hiding controls never changes either
      // constraint, scroll padding or the Scrollable's identity.
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        minHeight: stageHeight,
        maxHeight:
            stageHeight + (expandLyrics ? controls.height * progress : 0),
      ),
    );
    positionChild(AppPlayerHeaderSlot.stage, Offset.zero);
    positionChild(
      AppPlayerHeaderSlot.header,
      Offset(
        left,
        (contentHeight - header.height - 8) * (1 - progress) + 8 * progress,
      ),
    );
    if (hasChild(AppPlayerHeaderSlot.lyricsOptions)) {
      final options = layoutChild(
        AppPlayerHeaderSlot.lyricsOptions,
        BoxConstraints.loose(size),
      );
      positionChild(
        AppPlayerHeaderSlot.lyricsOptions,
        Offset(kAppPlayerContentInset, contentHeight - options.height - 8),
      );
    }
  }

  @override
  bool shouldRelayout(AppPlayerHeaderLayout oldDelegate) =>
      progress != oldDelegate.progress ||
      compactHeight != oldDelegate.compactHeight ||
      compactLeft != oldDelegate.compactLeft ||
      expandLyrics != oldDelegate.expandLyrics;
}
