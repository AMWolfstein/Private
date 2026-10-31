import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/models/automix_options.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/screens/player/equalizer_screen.dart';
import 'package:sistrum/services/playback/core/music_playback_deck.dart';
import 'package:sistrum/services/playback/music_player/music_player_service.dart'
    show resetAutoplayLearning;
import 'package:sistrum/utils/layout/nav_bar_inset.dart';
import 'package:sistrum/widgets/player/controls/app_volume_control.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/primitives/app_slider.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/settings/music_haptics_settings.dart';
import 'package:sistrum/widgets/settings/playback_normalization_settings.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';
import 'package:sistrum/widgets/status/beta_badge.dart';

part 'playback_settings_auto_mix_1.dart';
part 'playback_settings_auto_mix_2.dart';

class PlaybackSettingsPage extends ConsumerStatefulWidget {
  const PlaybackSettingsPage({super.key});

  @override
  ConsumerState<PlaybackSettingsPage> createState() =>
      _PlaybackSettingsPageState();
}

class AutoMixSettings extends ConsumerStatefulWidget {
  const AutoMixSettings({super.key});

  @override
  ConsumerState<AutoMixSettings> createState() => _AutoMixSettingsState();
}
