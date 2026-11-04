import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/primitives/app_surface.dart';
import 'package:sistrum/widgets/collection/app_metadata_row.dart';
import 'package:sistrum/widgets/player/artwork/player_artwork.dart';

/// Uses Sistrum's TrackInfoView layout: artwork header, then selectable values
/// below small labels, separated by thin dividers on one surface.
class AppPlayerDetailsSheet extends StatelessWidget {
  const AppPlayerDetailsSheet({
    super.key,
    required this.rows,
    required this.scrollController,
    this.mediaItem,
  });

  final List<(String, String)> rows;
  final ScrollController scrollController;
  final MediaItem? mediaItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = mediaItem;
    return AppSurface(
      radius: 0,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const AppSheetHandle(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.nowPlayingDetails,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      context.l10n.dialogDone,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SelectionArea(
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    if (item != null)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
                        sliver: SliverToBoxAdapter(
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox.square(
                                  dimension: 70,
                                  child: PlayerArtwork(
                                    artUri: item.artUri?.toString(),
                                    colorScheme: theme.colorScheme,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      item.artist ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyLarge
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (rows.isEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.all(24),
                        sliver: SliverToBoxAdapter(
                          child: Text(
                            context.l10n.nowPlayingNoMetadata,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        sliver: SliverList.builder(
                          itemCount: rows.length,
                          itemBuilder: (context, index) {
                            final (label, value) = rows[index];
                            return AppMetadataRow(
                              label: label,
                              value: value,
                              showDivider: index < rows.length - 1,
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
