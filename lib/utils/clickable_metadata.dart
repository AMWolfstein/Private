import 'package:flutter/material.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/screens/local_album_screen.dart';
import 'package:spotiflac_android/screens/local_artist_screen.dart';
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
  } catch (_) {}
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

/// The detail page a route shows, so a link to the page already on top keeps
/// it instead of stacking a copy.
class DetailPage {
  DetailPage.album(String name, {required String artistName})
    : kind = 'album',
      id =
          '${name.trim().toLowerCase()}\u0000'
          '${artistName.trim().toLowerCase()}';

  final String kind;
  final String id;

  bool matches(DetailPage other) => kind == other.kind && id == other.id;

  static final _routes = Expando<DetailPage>('detail page');

  /// Records that the route around [context] shows [page].
  static void mark(BuildContext context, DetailPage page) {
    final route = ModalRoute.of(context);
    if (route != null) _routes[route] = page;
  }

  static bool _isOnTop(NavigatorState navigator, DetailPage page) {
    Route<dynamic>? top;
    // Reads the top route without popping anything.
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    final shown = top == null ? null : _routes[top!];
    return shown != null && shown.matches(page);
  }
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
    if (page != null && DetailPage._isOnTop(navigator, page)) return;
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
