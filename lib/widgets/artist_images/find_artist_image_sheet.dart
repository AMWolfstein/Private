import 'package:sistrum/utils/logging/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:sistrum/core/theme/app_icons.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/artist_images/artist_image_providers.dart';
import 'package:sistrum/services/artist_images/artist_image_download.dart';
import 'package:sistrum/services/artist_images/artist_image_store.dart';
import 'package:sistrum/services/artist_images/deezer_artist_search.dart';
import 'package:sistrum/widgets/player/artwork/app_player_ground.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/primitives/app_context_menu.dart';
import 'package:sistrum/providers/animated_artwork/animated_artwork_providers.dart';
import 'package:sistrum/widgets/animated_artwork/find_animated_artwork_sheet.dart';

/// Opens the artist's three-dot menu. Find artist image opens the search
/// sheet; Reset image puts the album cover back.
Future<void> showArtistImageMenu(
  BuildContext context,
  WidgetRef ref,
  String artistName, {
  required bool hasPhoto,
  bool hasVideo = false,
  Rect? anchor,
}) async {
  final l10n = context.l10n;
  final action = await showAppContextMenu<String>(
    context: context,
    anchor: anchor,
    fitToAnchorSpace: true,
    builder: (menuContext) => AppContextMenu(
      groups: [
        [
          AppMenuAction(
            icon: appIconFor(Icons.person_search_outlined),
            label: l10n.artistOptionFindImage,
            onPressed: () => Navigator.of(menuContext).pop('find'),
          ),
          if (hasPhoto)
            AppMenuAction(
              icon: appIconFor(Icons.restart_alt),
              label: l10n.artistOptionResetImage,
              onPressed: () => Navigator.of(menuContext).pop('reset'),
            ),
        ],
        [
          AppMenuAction(
            icon: appIconFor(Icons.movie_outlined),
            label: l10n.animatedArtworkMenuFind,
            onPressed: () => Navigator.of(menuContext).pop('video_find'),
          ),
          if (hasVideo)
            AppMenuAction(
              icon: appIconFor(Icons.restart_alt),
              label: l10n.animatedArtworkMenuReset,
              onPressed: () => Navigator.of(menuContext).pop('video_reset'),
            ),
        ],
      ],
    ),
  );
  if (!context.mounted) return;
  if (action == 'video_find' || action == 'video_reset') {
    if (!context.mounted) return;
    await runAnimatedArtworkAction(
      context,
      ref,
      action: action == 'video_find' ? 'find' : 'reset',
      target: animatedArtistRef(artistName),
      title: artistName,
      artistName: null,
    );
    return;
  }
  if (action == 'find') {
    final saved = await showFindArtistImageSheet(context, artistName);
    if (saved == true) ref.invalidate(artistImageFileProvider(artistName));
  } else if (action == 'reset') {
    final store = ref.read(artistImageStoreProvider);
    final revision = ref.read(artistImageRevisionProvider.notifier);
    try {
      await store.recordWithoutPhoto(
        artistImageKey(artistName),
        ArtistImageStatus.reset,
      );
      revision.bump();
    } catch (error) {
      AppLogger('ArtistImages').w('Photo reset failed: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.artistImageSaveFailed)),
        );
      }
    }
  }
}

/// Search Deezer for an artist's photo and use the one the user picks.
/// Returns true when a photo was saved.
Future<bool?> showFindArtistImageSheet(
  BuildContext context,
  String artistName,
) {
  return showAppScrollableBottomSheet<bool>(
    context: context,
    title: context.l10n.artistImageFindTitle,
    builder: (context, scrollController) => FindArtistImageSheet(
      artistName: artistName,
      scrollController: scrollController,
    ),
  );
}

class FindArtistImageSheet extends ConsumerStatefulWidget {
  const FindArtistImageSheet({
    super.key,
    required this.artistName,
    required this.scrollController,
  });

  final String artistName;
  final ScrollController scrollController;

  @override
  ConsumerState<FindArtistImageSheet> createState() =>
      _FindArtistImageSheetState();
}

class _FindArtistImageSheetState extends ConsumerState<FindArtistImageSheet> {
  late final _query = TextEditingController(text: widget.artistName);
  List<DeezerArtist>? _results;
  DeezerArtist? _preview;
  bool _searching = false;
  bool _busy = false;
  String? _message;
  http.Client? _client;
  int _request = 0;

  @override
  void dispose() {
    _request++;
    _client?.close();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_busy) return;
    final l10n = context.l10n;
    final text = _query.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _searching = true;
      _message = null;
      _preview = null;
    });
    _client?.close();
    final request = ++_request;
    final client = http.Client();
    _client = client;
    try {
      final results = await DeezerArtistSearch(client).search(text);
      if (mounted && request == _request) setState(() => _results = results);
    } on DeezerUnavailable {
      if (mounted && request == _request) {
        setState(() => _message = l10n.artistImageSearchFailed);
      }
    } finally {
      client.close();
      if (mounted && request == _request) setState(() => _searching = false);
    }
  }

  Future<void> _use(DeezerArtist artist) async {
    final l10n = context.l10n;
    final url = artist.pictureUrl;
    if (url == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    if (_busy && _client != null) _client?.close();
    final request = ++_request;
    final store = ref.read(artistImageStoreProvider);
    final revision = ref.read(artistImageRevisionProvider.notifier);
    final client = http.Client();
    _client = client;
    try {
      final bytes = await downloadArtistImage(client, url);
      if (!mounted || request != _request) return;
      final result = await store.savePhoto(
        key: artistImageKey(widget.artistName),
        artist: artist,
        bytes: bytes,
        status: ArtistImageStatus.manual,
        mayCommit: () async => mounted && request == _request,
      );
      if (!mounted || request != _request) return;
      if (result == ArtistImageSaveOutcome.saved) {
        revision.bump();
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      AppLogger('ArtistImages').w('Artist photo save failed: $error');
      if (mounted) {
        setState(() {
          _busy = false;
          _message = error is ArtistImageDownloadFailed
              ? l10n.artistImageDownloadFailed
              : l10n.artistImageSaveFailed;
        });
      }
    } finally {
      client.close();
      if (identical(_client, client)) _client = null;
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return preview == null ? _buildSearch() : _buildPreview(preview);
  }

  Widget _buildSearch() {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final results = _results;
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        TextField(
          controller: _query,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(labelText: l10n.artistImageFindTitle),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _searching ? null : _search,
          child: Text(l10n.artistImageSearch),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 12),
        if (_searching)
          const LinearProgressIndicator()
        else if (results != null && results.isEmpty)
          Text(l10n.artistImageNoResults)
        else if (results != null)
          for (final artist in results)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundImage: artist.pictureUrl == null
                    ? null
                    : appCoverProvider(artist.pictureUrl),
                child: artist.pictureUrl == null
                    ? const Icon(Icons.person_outline)
                    : null,
              ),
              title: Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                artist.pictureUrl == null
                    ? l10n.artistImageNoPhoto
                    : l10n.artistImageCounts(artist.fans, artist.albums),
              ),
              onTap: artist.pictureUrl == null
                  ? null
                  : () => setState(() => _preview = artist),
            ),
      ],
    );
  }

  Widget _buildPreview(DeezerArtist artist) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: const BackButtonIcon(),
              onPressed: _busy ? null : () => setState(() => _preview = null),
            ),
            Expanded(
              child: Text(
                artist.name,
                style: theme.textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image(
              image: appCoverProvider(artist.pictureUrl)!,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : () => _use(artist),
          child: Text(l10n.artistImageUse),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }
}
