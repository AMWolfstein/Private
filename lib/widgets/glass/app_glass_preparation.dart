import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/theme/app_glass_levels.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/widgets/glass/app_glass_warmup.dart';
import 'package:sistrum/widgets/glass/app_artwork_glass.dart';

/// Starts the one-time preparation when the full glass theme is enabled,
/// including switching to Sistrum or enabling blur after the app has started.
class AppGlassPreparation extends ConsumerWidget {
  const AppGlassPreparation({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The artwork glass program loads at start whatever the level, so the
    // first menu over the player has nothing left to load.
    unawaited(AppArtworkGlassProgram.load());
    // Lenses appear on full glass above Level 1, and as touch-only thumbs
    // and segment pills under lite.
    if (ref.watch(appBlurEnabledProvider) &&
        !appGlassClarity(
          ref.watch(appGlassClarityLevelProvider),
        ).plainBlur &&
        !ref.watch(
          appGlassContrastBlockedProvider(
            MediaQuery.highContrastOf(context),
          ),
        )) {
      unawaited(AppGlassWarmup.prepare(View.of(context)));
      // Its pipeline too, where it can refract.
      if (ref.watch(appShaderFiltersSupportedProvider)) {
        unawaited(AppArtworkGlassProgram.prepare());
      }
    }
    return child;
  }
}
