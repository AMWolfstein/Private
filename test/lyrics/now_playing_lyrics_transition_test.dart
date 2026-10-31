import 'package:sistrum/core/navigation/app_screens.dart';
import 'package:sistrum/screens/shell/app_screens.dart';
import 'package:sistrum/screens/lyrics/lyrics_share_screen.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderParagraph, RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/providers/playback/player_metadata_controller.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/models/track.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/core/models/theme_settings.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/providers/settings/theme_provider.dart';
import 'package:sistrum/providers/library/library_collections_provider.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/screens/player/now_playing_screen.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/utils/lyrics/lyrics_parser.dart';
import 'package:sistrum/utils/lyrics/lyric_models.dart';
import 'package:sistrum/widgets/player/controls/app_volume_control.dart';
import 'package:sistrum/widgets/lyrics/lyric_gap_indicator.dart';
import 'package:sistrum/widgets/player/queue/app_player_queue.dart';
import 'package:sistrum/widgets/player/controls/app_playback_button.dart';
import 'package:sistrum/widgets/player/controls/app_playback_time.dart';
import 'package:sistrum/widgets/player/sheets/app_player_actions_sheet.dart';
import 'package:sistrum/widgets/player/controls/app_player_favorite_button.dart';
import 'package:sistrum/widgets/player/sheets/app_player_details_sheet.dart';
import 'package:sistrum/widgets/collection/app_metadata_row.dart';
import 'package:sistrum/widgets/glass/artwork/app_artwork_glass.dart';
import 'package:sistrum/widgets/glass/chrome/app_chrome.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_surface.dart';
import 'package:sistrum/widgets/player/artwork/app_player_background.dart';
import 'package:sistrum/widgets/player/mini_player.dart';
import 'package:sistrum/widgets/player/controls/playback_seek_slider.dart';

part 'now_playing_lyrics_transition_1.dart';
part 'now_playing_lyrics_transition_2.dart';
part 'now_playing_lyrics_transition_3.dart';
part 'now_playing_lyrics_transition_4.dart';
part 'now_playing_lyrics_transition_5.dart';
part 'now_playing_lyrics_transition_6.dart';
part 'now_playing_lyrics_transition_7.dart';
part 'now_playing_lyrics_transition_8.dart';
part 'now_playing_lyrics_transition_9.dart';
part 'now_playing_lyrics_transition_10.dart';
part 'now_playing_lyrics_transition_11.dart';
part 'now_playing_lyrics_transition_12.dart';
part 'now_playing_lyrics_transition_13.dart';
part 'now_playing_lyrics_transition_14.dart';
part 'now_playing_lyrics_transition_15.dart';

void main() {
  _registerNowPlayingLyricsTransition1();
  _registerNowPlayingLyricsTransition2();
  _registerNowPlayingLyricsTransition3();
  _registerNowPlayingLyricsTransition4();
  _registerNowPlayingLyricsTransition5();
  _registerNowPlayingLyricsTransition6();
  _registerNowPlayingLyricsTransition7();
  _registerNowPlayingLyricsTransition8();
  _registerNowPlayingLyricsTransition9();
  _registerNowPlayingLyricsTransition10();
  _registerNowPlayingLyricsTransition11();
  _registerNowPlayingLyricsTransition12();
  _registerNowPlayingLyricsTransition13();
  _registerNowPlayingLyricsTransition14();
  _registerNowPlayingLyricsTransition15();
}

Map<String, dynamic> _lyricsDto(ParsedLyrics value) => {
  'synced': value.synced,
  'wordSynced': value.wordSynced,
  'plainText': value.plainText,
  'writers': value.writers,
  'provider': value.provider,
  'lines': [
    for (final line in value.lines)
      {
        'timeMs': line.time.inMilliseconds,
        'endMs': line.end?.inMilliseconds,
        'text': line.text,
        'words': [for (final word in line.words) _wordDto(word)],
        'romanization': line.romanization,
        'romanizationWords': [
          for (final word in line.romanizationWords) _wordDto(word),
        ],
        'translation': line.translation,
        'voice': line.voice == null
            ? null
            : {
                'id': line.voice!.id,
                'index': line.voice!.index,
                'isGroup': line.voice!.isGroup,
              },
        'isBackground': line.isBackground,
        'vocalGroup': line.vocalGroup,
      },
  ],
};

Map<String, dynamic> _wordDto(LyricWord word) => {
  'timeMs': word.time.inMilliseconds,
  'endMs': word.end?.inMilliseconds,
  'text': word.text,
};

class _QueueController extends MusicPlayerController {
  _QueueController(this.onSelected);
  final void Function(int) onSelected;
  final selected = <int>[];

  @override
  Future<void> jumpTo(int index) async {
    selected.add(index);
    onSelected(index);
  }
}

class _SeekController extends MusicPlayerController {
  final seeks = <Duration>[];
  final completions = <Completer<void>>[];

  @override
  Future<void> seek(Duration position) {
    seeks.add(position);
    final completion = Completer<void>();
    completions.add(completion);
    return completion.future;
  }
}

class _TestCollections extends LibraryCollectionsNotifier {
  @override
  LibraryCollectionsState build() => LibraryCollectionsState(isLoaded: true);

  @override
  Future<bool> toggleLoved(Track track) async {
    final key = trackCollectionKey(track);
    final added = !state.isLoved(track);
    state = state.copyWith(
      loved: added
          ? [
              ...state.loved,
              CollectionTrackEntry(
                key: key,
                track: track,
                addedAt: DateTime.now(),
              ),
            ]
          : state.loved.where((entry) => entry.key != key).toList(),
    );
    return added;
  }
}
