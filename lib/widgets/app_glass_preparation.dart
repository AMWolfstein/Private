import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mornye/controllers/app_glass_warmup.dart';
import 'package:mornye/providers/runtime_profile_provider.dart';
import 'package:mornye/theme/app_theme.dart';

/// Starts the one-time preparation when the full glass theme is enabled,
/// including switching to Mornye or enabling blur after the app has started.
class AppGlassPreparation extends ConsumerWidget {
  const AppGlassPreparation({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (context.isMornye &&
        ref.watch(appGlassLevelProvider) == AppGlassLevel.liquid &&
        !ref.watch(
          appGlassContrastBlockedProvider(
            MediaQuery.highContrastOf(context),
          ),
        )) {
      unawaited(AppGlassWarmup.prepare(View.of(context)));
    }
    return child;
  }
}
