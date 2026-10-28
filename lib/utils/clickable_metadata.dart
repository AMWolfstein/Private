import 'package:flutter/material.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/screens/local_album_screen.dart';
import 'package:sistrum/screens/local_artist_screen.dart';
import 'package:sistrum/services/library/library_database.dart';
import 'package:sistrum/services/shell_navigation_service.dart';
import 'package:sistrum/utils/detail_page_route.dart';
import 'package:sistrum/utils/artist_utils.dart';
import 'package:sistrum/utils/logger.dart';

Future<void> navigateToArtistCredits(
  BuildContext context, {
  required String artistNames,
  String? artistIds,
}) async {
  final raw = artistNames.trim();
  if (raw.isEmpty) return;
  final names = splitArtistNames(raw);
  if (names.isEmpty) return;

  var name = names.first;
  if (names.length > 1) {
    // A comma can belong to the name ("Tyler, The Creator"). Keep the whole
    // credit when the scanned library knows it as one artist.
    try {
      final rows = await LibraryDatabase.instance.getQueueArtistPage(
        QueueLibraryDbQuery(searchQuery: raw, limit: 20),
      );
      for (final row in rows) {
        final artist = (row['artist_name'] as String? ?? '').trim();
        if (artist.toLowerCase() == raw.toLowerCase()) {
          name = artist;
          break;
        }
      }
    } catch (error) {
      AppLogger(
        'ClickableMetadata',
      ).w('Artist match lookup failed, using the first credit: $error');
    }
  }
  if (name.isEmpty || !context.mounted) return;
  await navigateToArtist(context, artistName: name);
}

Future<void> navigateToArtist(
  BuildContext context, {
  required String artistName,
  String? artistId,
  String? coverUrl,
}) async {
  if (artistName.isEmpty) return;
  pushViaPreferredNavigator(
    context,
    (_) =>
        LocalArtistScreen(artistName: artistName.trim(), coverPath: coverUrl),
  );
}

Future<void> navigateToAlbum(
  BuildContext context, {
  required String albumName,
  String? albumId,
  String? artistName,
  String? coverUrl,
}) async {
  if (albumName.isEmpty) return;

  List<Map<String, dynamic>> rows = const [];
  try {
    rows = await LibraryDatabase.instance.getQueueLocalAlbumTracks(
      albumName,
      (artistName ?? '').trim(),
    );
  } catch (error) {
    AppLogger(
      'ClickableMetadata',
    ).w('Album track lookup failed for "$albumName": $error');
  }
  if (!context.mounted) return;

  final tracks = rows.map(LocalLibraryItem.fromJson).toList(growable: false);
  if (tracks.isEmpty) {
    _showUnavailable(context, context.l10n.trackAlbum);
    return;
  }

  final first = tracks.first;
  final albumArtist = (first.albumArtist ?? '').trim();
  final pageArtist = albumArtist.isNotEmpty ? albumArtist : first.artistName;
  pushViaPreferredNavigator(
    context,
    (_) => LocalAlbumScreen(
      albumName: first.albumName,
      artistName: pageArtist,
      coverPath: first.coverPath,
      tracks: tracks,
    ),
    page: DetailPage.album(first.albumName, artistName: pageArtist),
  );
}

/// Pushes detail pages into the active tab navigator when invoked from a root
/// modal such as Now Playing. The root modal is dismissed first so the album
/// is immediately visible instead of being hidden behind it. A [page] that is
/// already on top is not pushed again.
void pushViaPreferredNavigator(
  BuildContext context,
  WidgetBuilder builder, {
  DetailPage? page,
}) {
  void push(NavigatorState navigator) {
    if (page != null && DetailPage.isOnTop(navigator, page)) return;
    navigator.push(MaterialPageRoute<void>(builder: builder));
  }

  final currentNavigator = Navigator.of(context);
  final rootNavigator = Navigator.of(context, rootNavigator: true);
  final activeTabNavigator = ShellNavigationService.activeTabNavigator();

  final shouldRouteToTabNavigator =
      identical(currentNavigator, rootNavigator) && activeTabNavigator != null;

  if (!shouldRouteToTabNavigator) {
    push(currentNavigator);
    return;
  }

  final currentRoute = ModalRoute.of(context);
  final shouldPopCurrentRoute =
      currentRoute != null && currentRoute.isFirst == false;

  if (shouldPopCurrentRoute && currentNavigator.canPop()) {
    currentNavigator.pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!activeTabNavigator.mounted) return;
      push(activeTabNavigator);
    });
    return;
  }

  push(activeTabNavigator);
}

void _showUnavailable(BuildContext context, String type) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(context.l10n.clickableInformationUnavailable(type))),
  );
}

class ClickableArtistName extends StatelessWidget {
  final String artistName;
  final String? artistId;
  final String? coverUrl;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const ClickableArtistName({
    super.key,
    required this.artistName,
    this.artistId,
    this.coverUrl,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => navigateToArtist(
        context,
        artistName: artistName,
        artistId: artistId,
        coverUrl: coverUrl,
      ),
      child: Text(
        artistName,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      ),
    );
  }
}

class ClickableAlbumName extends StatelessWidget {
  final String albumName;
  final String? albumId;
  final String? artistName;
  final String? coverUrl;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const ClickableAlbumName({
    super.key,
    required this.albumName,
    this.albumId,
    this.artistName,
    this.coverUrl,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      albumName,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
    return GestureDetector(
      onTap: () => navigateToAlbum(
        context,
        albumName: albumName,
        albumId: albumId,
        artistName: artistName,
        coverUrl: coverUrl,
      ),
      child: text,
    );
  }
}
