import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:sistrum/providers/player_metadata_controller.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/glass/app_artwork_glass.dart';
import 'package:sistrum/widgets/player/app_player_details_sheet.dart';

Future<void> showPlayerDetailsSheet(
  BuildContext context,
  ColorScheme colorScheme, {
  required PlayerMetadataController metadata,
  required MediaItem? mediaItem,
}) {
  final sistrum = context.isAppTheme;
  final fallback = metadata.detailsSnapshot(mediaItem);
  final metadataFuture = metadata.readDetails(mediaItem);
  // The sheet's glass draws from the player's artwork.
  final ground = AppArtworkGroundScope.forOverlays(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: sistrum,
    showDragHandle: !sistrum,
    backgroundColor: Colors.transparent,
    builder: (context) => AppArtworkGroundScope.wrapOverlay(
      ground,
      DraggableScrollableSheet(
        expand: false,
        initialChildSize: sistrum ? 0.75 : 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (context, scrollController) {
          return FutureBuilder<Map<String, dynamic>>(
            future: metadataFuture,
            initialData: fallback,
            builder: (context, snapshot) => _MetadataList(
              meta: snapshot.data ?? fallback,
              colorScheme: colorScheme,
              scrollController: scrollController,
              mediaItem: mediaItem,
            ),
          );
        },
      ),
    ),
  );
}

class _MetadataList extends StatelessWidget {
  final Map<String, dynamic> meta;
  final ColorScheme colorScheme;
  final ScrollController scrollController;
  final MediaItem? mediaItem;

  const _MetadataList({
    required this.meta,
    required this.colorScheme,
    required this.scrollController,
    this.mediaItem,
  });

  @override
  Widget build(BuildContext context) {
    String s(Object? v) => (v ?? '').toString();
    final l10n = context.l10n;
    final rows = <(String, String)>[
      (l10n.editMetadataFieldTitle, s(meta['title'])),
      (l10n.editMetadataFieldArtist, s(meta['artist'])),
      (l10n.editMetadataFieldAlbum, s(meta['album'])),
      (l10n.editMetadataFieldAlbumArtist, s(meta['album_artist'])),
      (l10n.editMetadataFieldGenre, s(meta['genre'])),
      (l10n.editMetadataFieldComposer, s(meta['composer'])),
      (l10n.editMetadataFieldDate, s(meta['date'])),
      (l10n.editMetadataFieldTrackNum, s(meta['track_number'])),
      (l10n.editMetadataFieldDiscNum, s(meta['disc_number'])),
      (l10n.editMetadataFieldIsrc, formatIsrcForDisplay(s(meta['isrc']))),
      (l10n.editMetadataFieldLabel, s(meta['label'])),
      (l10n.editMetadataFieldCopyright, s(meta['copyright'])),
      (l10n.libraryFilterFormat, s(meta['format']).toUpperCase()),
      (l10n.audioAnalysisCodec, s(meta['audio_codec'])),
      (
        l10n.audioAnalysisSampleRate,
        meta['sample_rate'] != null && (meta['sample_rate'] as num? ?? 0) > 0
            ? '${((meta['sample_rate'] as num) / 1000).toStringAsFixed(1)} kHz'
            : '',
      ),
      (
        l10n.audioAnalysisBitDepth,
        (meta['bit_depth'] as num? ?? 0) > 0 ? '${meta['bit_depth']}-bit' : '',
      ),
    ].where((r) => r.$2.trim().isNotEmpty && r.$2 != '0').toList();

    {
      return AppPlayerDetailsSheet(
        rows: rows,
        scrollController: scrollController,
        mediaItem: mediaItem,
      );
    }
  }
}

final RegExp _canonicalIsrcPattern = RegExp(r'^[A-Z]{2}[A-Z0-9]{3}\d{7}$');

String normalizeIsrc(String? value) =>
    (value ?? '').trim().toUpperCase().replaceAll(RegExp(r'[-\s]'), '');

/// Returns the compact canonical value only when [value] is a valid ISRC.
/// Invalid provider/tag values remain visible and copyable without mutation.
String canonicalIsrcForCopy(String? value) {
  final original = value?.trim() ?? '';
  final normalized = normalizeIsrc(original);
  return _canonicalIsrcPattern.hasMatch(normalized) ? normalized : original;
}

/// Formats a valid canonical ISRC for display without changing stored tags.
///
/// Example: `AA9BQ2200061` becomes `AA-9BQ-22-00061`.
String formatIsrcForDisplay(String? value) {
  final original = value?.trim() ?? '';
  final canonical = canonicalIsrcForCopy(original);
  if (!_canonicalIsrcPattern.hasMatch(canonical)) {
    return original;
  }
  return '${canonical.substring(0, 2)}-'
      '${canonical.substring(2, 5)}-'
      '${canonical.substring(5, 7)}-'
      '${canonical.substring(7)}';
}
