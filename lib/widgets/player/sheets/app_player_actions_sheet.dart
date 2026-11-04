import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/library/library_collections_provider.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/services/library/covers/cover_palette.dart';
import 'package:sistrum/core/theme/app_icons.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/primitives/app_context_menu.dart';
import 'package:sistrum/providers/library/cover_palette_provider.dart';

/// Navigation for the title/artist, separate from playback and file actions.
class AppPlayerNavigationMenu extends StatelessWidget {
  const AppPlayerNavigationMenu({super.key, required this.mediaItem});

  final MediaItem mediaItem;

  @override
  Widget build(BuildContext context) {
    return _AppPlayerMenuSurface(
      mediaItem: mediaItem,
      child: AppContextMenu(
        inheritSurface: true,
        dense: true,
        groups: [
          [
            if ((mediaItem.artist ?? '').trim().isNotEmpty)
              AppMenuAction(
                icon: CupertinoIcons.mic,
                label: context.l10n.appGoToArtist,
                subtitle: mediaItem.artist,
                onPressed: () => Navigator.of(context).pop('artist'),
              ),
            if ((mediaItem.album ?? '').trim().isNotEmpty)
              AppMenuAction(
                icon: CupertinoIcons.square_stack,
                label: context.l10n.homeGoToAlbum,
                subtitle: mediaItem.album,
                onPressed: () => Navigator.of(context).pop('album'),
              ),
          ],
        ],
      ),
    );
  }
}

/// A floating menu that inherits the player's dark appearance.
class AppPlayerActionsSheet extends ConsumerWidget {
  const AppPlayerActionsSheet({
    super.key,
    required this.mediaItem,
    this.sleepTimerSubtitle,
  });

  final MediaItem mediaItem;
  final String? sleepTimerSubtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(playerCollectionTrackProvider(mediaItem)).value;
    final loved = ref.watch(
      libraryCollectionsProvider.select(
        (state) => track != null && state.isLoved(track),
      ),
    );
    return _AppPlayerMenuSurface(
      mediaItem: mediaItem,
      child: AppContextMenu(
        inheritSurface: true,
        dense: true,
        quickActions: [
          _action(
            context,
            'favorite',
            loved ? context.l10n.appFavorited : context.l10n.appFavorite,
            loved ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
            selected: loved,
          ),
          _action(
            context,
            'share',
            context.l10n.trackMetadataShare,
            CupertinoIcons.share_solid,
          ),
        ],
        groups: [
          [
            _action(
              context,
              'playlist',
              context.l10n.collectionAddToPlaylist,
              CupertinoIcons.text_badge_plus,
            ),
          ],
          [
            if ((mediaItem.album ?? '').trim().isNotEmpty)
              _action(
                context,
                'album',
                context.l10n.homeGoToAlbum,
                CupertinoIcons.square_stack,
                subtitle: mediaItem.album,
              ),
            if ((mediaItem.artist ?? '').trim().isNotEmpty)
              _action(
                context,
                'artist',
                context.l10n.appGoToArtist,
                CupertinoIcons.mic,
                subtitle: mediaItem.artist,
              ),
            _action(
              context,
              'details',
              context.l10n.nowPlayingDetails,
              CupertinoIcons.info,
            ),
            _action(
              context,
              'shareLyrics',
              context.l10n.lyricsShareTitle,
              CupertinoIcons.quote_bubble,
            ),
            _action(
              context,
              'fetchLyrics',
              context.l10n.lyricsFindMenu,
              CupertinoIcons.search,
            ),
          ],
          [
            _action(
              context,
              'volume',
              ref.watch(settingsProvider.select((s) => s.playerShowVolume))
                  ? context.l10n.nowPlayingHideVolumeSlider
                  : context.l10n.nowPlayingShowVolumeSlider,
              CupertinoIcons.speaker_2,
            ),
            _action(
              context,
              'equalizer',
              context.l10n.equalizerTitle,
              CupertinoIcons.slider_horizontal_3,
            ),
            _action(
              context,
              'sleepTimer',
              context.l10n.nowPlayingSleepTimer,
              CupertinoIcons.moon_zzz,
              subtitle: sleepTimerSubtitle,
            ),
          ],
          [
            _action(
              context,
              'delete',
              context.l10n.trackRemoveFromDevice,
              appIconFor(Icons.delete_outline),
              destructive: true,
            ),
          ],
        ],
      ),
    );
  }

  AppMenuAction _action(
    BuildContext context,
    String value,
    String label,
    IconData icon, {
    String? subtitle,
    bool selected = false,
    bool destructive = false,
  }) => AppMenuAction(
    icon: icon,
    label: label,
    subtitle: subtitle,
    selected: selected,
    destructive: destructive,
    onPressed: () => Navigator.of(context).pop(value),
  );
}

/// Reuse the cached cover palette; no per-frame background capture is needed.
class _AppPlayerMenuSurface extends StatelessWidget {
  const _AppPlayerMenuSurface({required this.mediaItem, required this.child});

  final MediaItem mediaItem;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final art = mediaItem.artUri;
    final source = art?.scheme == 'file' ? art!.toFilePath() : art?.toString();
    return CoverPaletteBuilder(
      palette: paletteOf(context),
      imageSource: source,
      builder: (context, _) {
        final surface = paletteOf(context).colors(source).menuSurface;
        return Theme(
          data: AppTheme.fromContext(
            context,
            brightness: Brightness.dark,
            chromeSurface: surface,
          ),
          child: child,
        );
      },
    );
  }
}
