import 'package:sistrum/widgets/cached_cover_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/screens/library/local_artist_screen.dart';
import 'package:sistrum/utils/adaptive_layout.dart';
import 'package:sistrum/utils/nav_bar_inset.dart';
import 'package:sistrum/widgets/animation_utils.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';

class FavoriteArtistsScreen extends ConsumerWidget {
  const FavoriteArtistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(
      libraryCollectionsProvider.select((state) => state.favoriteArtists),
    );
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = context.navBarBottomInset;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          AppSliverHeader.page(title: context.l10n.collectionFavoriteArtists),
          if (artists.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.favorite,
                        size: 60,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.l10n.collectionFavoriteArtistsEmptyTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.l10n.collectionFavoriteArtistsEmptySubtitle,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: wideListInset(context)),
              sliver: SliverList.separated(
                itemCount: artists.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final artist = artists[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: _ArtistThumbnail(artist: artist),
                    title: Text(
                      artist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: context.l10n.artistOptionRemoveFromFavorites,
                      icon: Icon(Icons.favorite, color: colorScheme.error),
                      onPressed: () async {
                        await ref
                            .read(libraryCollectionsProvider.notifier)
                            .removeFavoriteArtist(artist.key);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              context.l10n.collectionRemovedFromFavoriteArtists(
                                artist.name,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        slidePageRoute<void>(
                          page: LocalArtistScreen(
                            artistName: artist.name,
                            coverPath: artist.imageUrl,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          SliverToBoxAdapter(child: SizedBox(height: bottomInset)),
        ],
      ),
    );
  }
}

class _ArtistThumbnail extends StatelessWidget {
  final CollectionArtistEntry artist;

  const _ArtistThumbnail({required this.artist});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final imageUrl = artist.imageUrl;
    return ClipOval(
      child: imageUrl != null && imageUrl.isNotEmpty
          ? CachedCoverImage(
              imageUrl: imageUrl,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              memCacheWidth: 112,
              memCacheHeight: 112,

              errorWidget: (_, _, _) => _placeholder(colorScheme),
            )
          : _placeholder(colorScheme),
    );
  }

  Widget _placeholder(ColorScheme colorScheme) {
    return Container(
      width: 56,
      height: 56,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(Icons.person, color: colorScheme.onSurfaceVariant),
    );
  }
}
