import 'package:flutter/material.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/local_library_item.dart';
import 'package:sistrum/navigation/app_screens.dart';
import 'package:sistrum/navigation/shell_navigation.dart';
import 'package:sistrum/services/library/library_tag_credits.dart';
import 'package:sistrum/services/library/library_database.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/utils/detail_page_route.dart';
import 'package:sistrum/utils/logger.dart';

/// Opens the artist named by a credit. A comma, "&" or "feat." splits the
/// credit into artists (see [TagCreditRules]); one artist opens directly,
/// several open a picker.
Future<void> navigateToArtistCredits(
  BuildContext context, {
  required String artistNames,
  required TagCreditRules rules,
}) async {
  final names = splitTagCredits(artistNames, TagCreditField.artist, rules);
  if (names.isEmpty || !context.mounted) return;
  if (names.length == 1) {
    await navigateToArtist(context, artistName: names.single);
    return;
  }
  final name = await showAppBottomSheet<String>(
    context: context,
    title: context.l10n.appGoToArtist,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final name in names)
          ListTile(
            title: Text(name),
            onTap: () => Navigator.pop(sheetContext, name),
          ),
      ],
    ),
  );
  if (name == null || !context.mounted) return;
  await navigateToArtist(context, artistName: name);
}

Future<void> navigateToArtist(
  BuildContext context, {
  required String artistName,
  String? coverUrl,
}) => Future.sync(() {
  if (artistName.isEmpty) return;
  final screens = appScreensOf(context);
  pushViaPreferredNavigator(
    context,
    (_) => screens.artist(artistName: artistName.trim(), coverPath: coverUrl),
  );
});

Future<void> navigateToAlbum(
  BuildContext context, {
  required LibraryDatabase database,
  required String albumName,
  String? albumId,
  String? artistName,
  String? coverUrl,
}) async {
  if (albumName.isEmpty) return;

  List<Map<String, dynamic>> rows = const [];
  try {
    rows = await database.getBrowseLocalAlbumRows(
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
  final screens = appScreensOf(context);
  pushViaPreferredNavigator(
    context,
    (_) => screens.album(
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
  final String? coverUrl;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const ClickableArtistName({
    super.key,
    required this.artistName,
    this.coverUrl,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () =>
          navigateToArtist(context, artistName: artistName, coverUrl: coverUrl),
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
