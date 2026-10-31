import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/models/app_glass.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:sistrum/core/theme/app_glass_levels.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/glass/thumb/app_liquid_backdrop.dart';
import 'package:sistrum/widgets/primitives/app_switch.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_surface.dart';
import 'package:sistrum/widgets/glass/chrome/app_chrome_controls.dart';
import 'package:sistrum/widgets/glass/selection/app_selection_pill.dart';

part 'app_glass_level_1.dart';
part 'app_glass_level_2.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();

  @override
  void setGlassQuality(AppGlassQuality quality) {
    state = state.copyWith(glassQuality: quality.name);
  }
}

AppGlassLevel _levelFor({
  required bool lowEnd,
  required AppGlassQuality quality,
  required bool liquidCapable,
}) {
  final container = ProviderContainer(
    overrides: [
      lowEndDeviceProvider.overrideWithValue(lowEnd),
      appGlassQualityProvider.overrideWithValue(quality),
      deviceSupportsLiquidGlassProvider.overrideWithValue(liquidCapable),
    ],
  );
  addTearDown(container.dispose);
  return container.read(appGlassLevelProvider);
}

void main() {
  _registerAppGlassLevel1();
  _registerAppGlassLevel2();
}
