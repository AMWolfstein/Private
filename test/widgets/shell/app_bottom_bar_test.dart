import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:sistrum/core/models/app_glass.dart';
import 'package:sistrum/widgets/glass/selection/app_selection_pill.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/screens/settings/settings_tab.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/utils/layout/nav_bar_inset.dart';
import 'package:sistrum/widgets/header/album_detail_header.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/collection/collection_scaffold.dart';
import 'package:sistrum/widgets/player/mini_player.dart';
import 'package:sistrum/widgets/glass/chrome/app_backdrop_groups.dart';
import 'package:sistrum/widgets/header/app_artist_header.dart';
import 'package:sistrum/widgets/shell/app_bottom_bar.dart';
import 'package:sistrum/widgets/glass/chrome/app_chrome_controls.dart';

part 'app_bottom_bar_shared_read.dart';
part 'app_bottom_bar_transitions.dart';
part 'app_bottom_bar_folding.dart';

void main() {
  _registerAppBottomBarSharedRead();
  _registerAppBottomBarTransitions();
  _registerAppBottomBarFolding();
}

class _StripedBackdrop extends CustomPainter {
  const _StripedBackdrop();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    // Clear glass uses a small blur; fine stripes still reveal a lost backdrop
    // during transforms without requiring the old heavily frosted appearance.
    for (var x = 0.0; x < size.width; x += 2) {
      paint.color = (x / 2).round().isEven ? Colors.white : Colors.black;
      canvas.drawRect(Rect.fromLTWH(x, 0, 2, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_StripedBackdrop oldDelegate) => false;
}
