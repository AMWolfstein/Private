import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/theme/mornye_glass_levels.dart';
import 'package:spotiflac_android/providers/runtime_profile_provider.dart';
import 'package:spotiflac_android/services/mornye_glass_warmup.dart';
import 'package:spotiflac_android/widgets/mornye_artwork_glass.dart';

/// Starts the one-time preparation when the full glass theme is enabled,
/// including switching to Mornye or enabling blur after the app has started.
class MornyeGlassPreparation extends ConsumerWidget {
  const MornyeGlassPreparation({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The artwork glass program loads at start whatever the level, so the
    // first menu over the player has nothing left to load.
    unawaited(MornyeArtworkGlassProgram.load());
    // Lenses appear on full glass above Level 1, and as touch-only thumbs
    // and segment pills under lite.
    if (ref.watch(mornyeBlurEnabledProvider) &&
        !mornyeGlassClarity(
          ref.watch(mornyeGlassClarityLevelProvider),
        ).plainBlur &&
        !ref.watch(
          mornyeGlassContrastBlockedProvider(
            MediaQuery.highContrastOf(context),
          ),
        )) {
      unawaited(MornyeGlassWarmup.prepare(View.of(context)));
      // Its pipeline too, where it can refract.
      if (ref.watch(mornyeShaderFiltersSupportedProvider)) {
        unawaited(MornyeArtworkGlassProgram.prepare());
      }
    }
    return child;
  }
}
