import 'package:sistrum/screens/equalizer_screen.dart';
import 'package:sistrum/screens/lyrics_share_screen.dart';
import 'package:sistrum/utils/lyrics/lyric_models.dart';
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sistrum/providers/library_database_provider.dart';
import 'package:sistrum/providers/library_tag_credits_provider.dart';
import 'package:sistrum/providers/player_metadata_controller.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/providers/theme_provider.dart';
import 'package:sistrum/core/models/theme_settings.dart';
import 'package:sistrum/core/navigation/now_playing_route.dart';
import 'package:sistrum/screens/library/local_album/local_album_screen.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/core/navigation/detail_navigation.dart';
import 'package:sistrum/utils/playback/playback_seek_preview.dart';
import 'package:sistrum/utils/logging/logger.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/status/audio_output_button.dart';
import 'package:sistrum/widgets/lyrics/lyrics_screen_awake.dart';
import 'package:sistrum/widgets/header/album_ken_burns.dart';
import 'package:sistrum/widgets/player/artwork/player_artwork.dart';
import 'package:sistrum/widgets/player/layout/player_track_swipe.dart';
import 'package:sistrum/widgets/player/layout/player_gesture_regions.dart';
import 'package:sistrum/widgets/player/sheets/player_details_sheet.dart';
import 'package:sistrum/widgets/player/layout/app_player_layout.dart';
import 'package:sistrum/widgets/player/lyrics/player_lyrics_controls.dart';
import 'package:sistrum/widgets/player/lyrics/player_lyrics_section.dart';
import 'package:sistrum/widgets/sheets/playlist_picker_sheet.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';
import 'package:sistrum/widgets/player/artwork/app_player_background.dart';
import 'package:sistrum/widgets/player/artwork/app_player_ground.dart';
import 'package:sistrum/widgets/glass/artwork/app_artwork_contrast.dart';
import 'package:sistrum/widgets/player/sheets/app_player_actions_sheet.dart';
import 'package:sistrum/widgets/primitives/app_context_menu.dart';

export 'package:sistrum/core/navigation/now_playing_route.dart';

part 'now_playing_screen_player.dart';
part 'now_playing_screen_lyrics.dart';
part 'now_playing_screen_menus.dart';

final _log = AppLogger('NowPlaying');

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key, this.metadataControllerFactory});

  final PlayerMetadataController Function()? metadataControllerFactory;

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  ProviderSubscription<AsyncValue<MediaItem?>>? _mediaItemSub;
  ProviderSubscription<bool>? _lyricsPlayingSub;
  late final _trackMetadata =
      widget.metadataControllerFactory?.call() ?? PlayerMetadataController();
  int _currentPage = 0;
  bool _landscape = false;

  bool _lyricsControlsHidden = false;
  bool _lyricsOptionsOpen = false;
  bool _audioOutputOpen = false;
  bool _sharingLyrics = false;
  double _lyricsScrollDistance = 0;
  Timer? _lyricsIdleTimer;
  final _lyricsPointers = <int, Offset>{};
  bool _lyricsPointerMoved = false;
  final _artworkHeaderKey = GlobalKey();
  final _artworkControlsKey = GlobalKey();
  final _artworkVolumeKey = GlobalKey();
  final _expandedArtworkKey = GlobalKey();
  final _immersiveArtworkKey = GlobalKey();
  final _compactArtworkKey = GlobalKey();
  final _artworkForeground = ValueNotifier<Map<String, Color>>({});
  final _seekPreview = PlaybackSeekPreview();
  NowPlayingRoute? _artworkRoute;

  @override
  void initState() {
    super.initState();
    _mediaItemSub = ref.listenManual<AsyncValue<MediaItem?>>(
      currentMediaItemProvider,
      (previous, next) {
        if (previous?.value?.id != next.value?.id) _seekPreview.reset();
        unawaited(
          _trackMetadata.load(
            next.value,
            inspectUnresolvedContentUri: _lyricsWanted,
          ),
        );
      },
    );
    _lyricsPlayingSub = ref.listenManual<bool>(playbackPlayingProvider, (
      previous,
      playing,
    ) {
      if (!playing && _lyricsControlsHidden) {
        setState(() => _lyricsControlsHidden = false);
      }
      _scheduleLyricsControlsHide();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        _trackMetadata.load(
          ref.read(currentMediaItemProvider).value,
          inspectUnresolvedContentUri: _lyricsWanted,
        ),
      );
    });
  }

  /// Lyrics are read from an unresolved SAF document only when they show:
  /// on the lyrics page, or above the seek bar when that strip is on.
  bool get _lyricsWanted =>
      _currentPage == 1 || ref.read(settingsProvider).lyricsAboveSeekBar;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    _landscape = size.width > size.height;
    if (_landscape || MediaQuery.accessibleNavigationOf(context)) {
      _lyricsControlsHidden = false;
    }
    _scheduleLyricsControlsHide();
  }

  @override
  void dispose() {
    _artworkRoute?.readArtwork = null;
    _lyricsIdleTimer?.cancel();
    _mediaItemSub?.close();
    _lyricsPlayingSub?.close();
    _trackMetadata.dispose();
    _artworkForeground.dispose();
    _seekPreview.dispose();
    super.dispose();
  }

  void _rebuild(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    return LyricsScreenAwake(
      visible:
          _currentPage == 1 &&
          ref.watch(currentMediaItemProvider).value != null,
      child: _buildPlayer(context),
    );
  }
}
