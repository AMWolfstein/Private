import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/services/library/cover_palette.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/widgets/primitives/sistrum_context_menu.dart';
import 'package:sistrum/providers/cover_palette_provider.dart';

/// Navigation for the title/artist, separate from playback and file actions.
class SistrumPlayerNavigationMenu extends StatelessWidget {
  const SistrumPlayerNavigationMenu({super.key, required this.mediaItem});

  final MediaItem mediaItem;

  @override
  Widget build(BuildContext context) {
    return _SistrumPlayerMenuSurface(
      mediaItem: mediaItem,
      child: SistrumContextMenu(
        inheritSurface: true,
        dense: true,
        groups: [
          [
            if ((mediaItem.artist ?? '').trim().isNotEmpty)
              SistrumMenuAction(
                icon: CupertinoIcons.mic,
                label: context.l10n.sistrumGoToArtist,
                subtitle: mediaItem.artist,
                onPressed: () => Navigator.of(context).pop('artist'),
              ),
            if ((mediaItem.album ?? '').trim().isNotEmpty)
              SistrumMenuAction(
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
class SistrumPlayerActionsSheet extends ConsumerWidget {
  const SistrumPlayerActionsSheet({
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
    return _SistrumPlayerMenuSurface(
      mediaItem: mediaItem,
      child: SistrumContextMenu(
        inheritSurface: true,
        dense: true,
        quickActions: [
          _action(
            context,
            'favorite',
            loved
                ? context.l10n.sistrumFavorited
                : context.l10n.sistrumFavorite,
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
                context.l10n.sistrumGoToArtist,
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
          ],
          [
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
        ],
      ),
    );
  }

  SistrumMenuAction _action(
    BuildContext context,
    String value,
    String label,
    IconData icon, {
    String? subtitle,
    bool selected = false,
  }) => SistrumMenuAction(
    icon: icon,
    label: label,
    subtitle: subtitle,
    selected: selected,
    onPressed: () => Navigator.of(context).pop(value),
  );
}

/// Reuse the cached cover palette; no per-frame background capture is needed.
class _SistrumPlayerMenuSurface extends StatelessWidget {
  const _SistrumPlayerMenuSurface({
    required this.mediaItem,
    required this.child,
  });

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
          data: SistrumTheme.fromContext(
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
