import 'package:flutter/material.dart';
import 'package:sistrum/providers/library_browse_provider.dart';
import 'package:sistrum/widgets/cached_cover_image.dart';
import 'package:sistrum/widgets/library/local_library_artwork_builder.dart';

class LibraryBrowseArtwork extends StatelessWidget {
  const LibraryBrowseArtwork({super.key, required this.entry});
  final LibraryBrowseEntry entry;

  @override
  Widget build(BuildContext context) {
    Widget fallback(BuildContext context) => ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.album_outlined,
          size: 40,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
    return LocalLibraryArtworkBuilder(
      coverPath: entry.cover,
      filePath: entry.samplePath,
      builder: (context, cover) => cover == null
          ? fallback(context)
          : LocalCoverImage(url: cover, placeholder: fallback),
    );
  }
}
