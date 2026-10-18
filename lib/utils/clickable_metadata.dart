import 'package:flutter/material.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/screens/local_album_screen.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/services/shell_navigation_service.dart';

Future<void> navigateToArtistCredits(
  BuildContext context, {
  required String artistNames,
  String? artistIds,
}) async {
  final name = artistNames.split(RegExp(r'\s*,\s*')).first.trim();
  if (name.isEmpty) return;
  await navigateToArtist(context, artistName: name);
}

Future<void> navigateToArtist(
  BuildContext context, {
  required String artistName,
  String? artistId,
  String? coverUrl,
}) async {
  if (artistName.isEmpty) return;
  _showUnavailable(context, context.l10n.trackArtist);
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
  } catch (_) {}
  if (!context.mounted) return;

  final tracks = rows.map(LocalLibraryItem.fromJson).toList(growable: false);
  if (tracks.isEmpty) {
    _showUnavailable(context, context.l10n.trackAlbum);
    return;
  }

  final first = tracks.first;
  final albumArtist = (first.albumArtist ?? '').trim();
  pushViaPreferredNavigator(
    context,
    (_) => LocalAlbumScreen(
      albumName: first.albumName,
      artistName: albumArtist.isNotEmpty ? albumArtist : first.artistName,
      coverPath: first.coverPath,
      tracks: tracks,
    ),
  );
}

/// Opens the album for a track. Local-only builds match the track's album
/// name and artist against the scanned library instead of remote providers.
Future<void> navigateToTrackAlbum(BuildContext context, Track track) async {
  final albumName = track.albumName.trim();
  if (albumName.isEmpty) return;
  await navigateToAlbum(
    context,
    albumName: albumName,
    artistName: _preferredAlbumArtist(track),
    coverUrl: track.coverUrl,
  );
}

String _preferredAlbumArtist(Track track) {
  final albumArtist = (track.albumArtist ?? '').trim();
  return albumArtist.isNotEmpty ? albumArtist : track.artistName;
}

/// Pushes detail pages into the active tab navigator when invoked from a root
/// modal such as Now Playing. The root modal is dismissed first so the album
/// is immediately visible instead of being hidden behind it.
void pushViaPreferredNavigator(BuildContext context, WidgetBuilder builder) {
  final currentNavigator = Navigator.of(context);
  final rootNavigator = Navigator.of(context, rootNavigator: true);
  final activeTabNavigator = ShellNavigationService.activeTabNavigator();

  final shouldRouteToTabNavigator =
      identical(currentNavigator, rootNavigator) && activeTabNavigator != null;

  if (!shouldRouteToTabNavigator) {
    currentNavigator.push(MaterialPageRoute<void>(builder: builder));
    return;
  }

  final currentRoute = ModalRoute.of(context);
  final shouldPopCurrentRoute =
      currentRoute != null && currentRoute.isFirst == false;

  if (shouldPopCurrentRoute && currentNavigator.canPop()) {
    currentNavigator.pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!activeTabNavigator.mounted) return;
      activeTabNavigator.push(MaterialPageRoute<void>(builder: builder));
    });
    return;
  }

  activeTabNavigator.push(MaterialPageRoute<void>(builder: builder));
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
    return Text(
      artistName,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
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
