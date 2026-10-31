import 'dart:async';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/core/navigation/app_screens.dart';
import 'package:sistrum/screens/shell/app_screens.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/providers/library/local_library_provider.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/screens/library/local_artist/local_artist_screen.dart';
import 'package:sistrum/widgets/library/track_metadata_edit_sheet.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/library/local_song_menu.dart';
import 'package:sistrum/widgets/library/local_song_row.dart';
import 'package:sistrum/widgets/primitives/app_context_menu.dart';
import '../../support/pump_until.dart';

part 'local_song_menu_popover.dart';
part 'local_song_menu_navigation.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

class _Local extends LocalLibraryNotifier {
  final removedItemIds = <String>[];
  final removedPaths = <String>[];
  @override
  LocalLibraryState build() => LocalLibraryState();
  @override
  Future<void> removePhysicalFiles(Iterable<String> paths) async =>
      removedPaths.addAll(paths);
  @override
  Future<void> removeItems(Iterable<String> ids) async =>
      removedItemIds.addAll(ids);
}

class _Player extends MusicPlayerController {
  final nextIds = <String>[], queued = <String>[];
  @override
  Future<void> playNextLocal(LocalLibraryItem item) async =>
      nextIds.add(item.id);
  @override
  Future<void> addToQueueLocal(LocalLibraryItem item) async =>
      queued.add(item.id);
}

void main() {
  _registerLocalSongMenuPopover();
  _registerLocalSongMenuNavigation();
}
