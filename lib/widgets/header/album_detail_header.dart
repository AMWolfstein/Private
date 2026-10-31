import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxySliver;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/library/cover_palette_provider.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/services/library/covers/cover_palette.dart';
import 'package:sistrum/core/theme/app_tokens.dart';
import 'package:sistrum/widgets/glass/artwork/app_artwork_page_ground.dart';
import 'package:sistrum/widgets/glass/chrome/app_floating_header.dart';
import 'package:sistrum/widgets/header/header_controls.dart';

part 'album_detail_header_title.dart';
part 'album_detail_header_slivers.dart';
part 'album_detail_header_app_bars.dart';

part 'album_detail_header_parts.dart';

/// Collapsing album-detail header shared by the album and local-album
/// screens: full-bleed [background] (optionally blurred and
/// scrimmed), bottom gradient, centered square cover, title, optional
/// subtitle/meta/actions rows, and a circular back button. Content fades out
/// below 30% expansion; the [title] fades into the toolbar instead.
///
/// Colours come from a scheme derived from [paletteSource] (see [CoverPalette])
/// and are published to descendants through [HeaderPalette], so the header
/// follows both the artwork and the app's light/dark mode instead of assuming a
/// black backdrop with white text.
class AlbumDetailHeader extends StatelessWidget {
  const AlbumDetailHeader({
    super.key,
    required this.title,
    required this.expandedHeight,
    required this.showTitleInAppBar,
    required this.background,
    this.paletteSource,
    this.blurAndScrimBackground = true,
    this.coverBuilder,
    this.subtitle,
    this.meta,
    this.actions,
    this.appBarActions,
    this.appBarTitle,
    this.leading,
    this.backgroundColor,
    this.immersive = false,
    this.squareArtwork = true,
  });

  final String title;
  final double expandedHeight;
  final bool showTitleInAppBar;

  /// Full-bleed background content (cover image, motion banner, placeholder).
  final Widget background;

  /// Cover URL or local path the header palette is derived from. Null keeps the
  /// app's own colour scheme.
  final String? paletteSource;

  /// Blur the background and dim it 35%; disable for motion banners and
  /// placeholder backgrounds.
  final bool blurAndScrimBackground;

  /// Builds the centered square cover for the given side length; null hides
  /// the cover block (the header wraps it in the shared shadow + rounding).
  final Widget Function(BuildContext context, double coverSize)? coverBuilder;

  /// Artist line under the title (plain text or a clickable artist widget).
  final Widget? subtitle;

  /// "•"-joined meta row under the subtitle.
  final Widget? meta;

  /// Action row (play/shuffle, download-all, ...) under the meta row.
  final Widget? actions;

  /// Extra toolbar actions (top-right).
  final List<Widget>? appBarActions;

  /// Toolbar title when it should differ from [title] (e.g. a selection
  /// count); defaults to [title].
  final String? appBarTitle;

  /// Replaces the default circular back button.
  final Widget? leading;

  final Color? backgroundColor;
  final bool immersive;

  /// Ordinary cover art stays 1:1; provider-supplied banners may fill a header.
  final bool squareArtwork;

  @override
  Widget build(BuildContext context) {
    if ((coverBuilder != null || immersive)) {
      final scheme = Theme.of(context).colorScheme;
      return HeaderPalette(
        scheme: scheme,
        child: Builder(
          builder: (context) =>
              SliverMainAxisGroup(slivers: buildSlivers(context)),
        ),
      );
    }
    return CoverPaletteBuilder(
      palette: paletteOf(context),
      imageSource: paletteSource,
      builder: (context, headerScheme) => _buildAppBar(context, headerScheme),
    );
  }
}

/// Primary action pill in a detail header (download all, play all). Reads its
/// colours from [HeaderPalette] so it works on light and dark headers alike.
