import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:sistrum/core/theme/app_icons.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/animated_artwork/animated_artwork_providers.dart';
import 'package:sistrum/services/animated_artwork/animated_artwork_download.dart';
import 'package:sistrum/services/animated_artwork/animated_artwork_manual.dart';
import 'package:sistrum/services/animated_artwork/animated_artwork_store.dart';
import 'package:sistrum/services/animated_artwork/apple_artwork_client.dart';
import 'package:sistrum/services/animated_artwork/apple_artwork_parse.dart';
import 'package:sistrum/utils/logging/logger.dart';
import 'package:sistrum/widgets/animated_artwork/animated_artwork_video.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/primitives/app_context_menu.dart';

/// The three-dot action for an album or artist: Find animated artwork opens
/// the search sheet, and Reset animated artwork returns to the static cover.
/// Returns true when the artwork changed.
Future<bool> showAnimatedArtworkMenu(
  BuildContext context,
  WidgetRef ref, {
  required AnimatedArtworkRef target,
  required String title,
  required String? artistName,
  int? trackCount,
  required bool hasVideo,
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
            icon: appIconFor(Icons.movie_outlined),
            label: l10n.animatedArtworkMenuFind,
            onPressed: () => Navigator.of(menuContext).pop('find'),
          ),
          if (hasVideo)
            AppMenuAction(
              icon: appIconFor(Icons.restart_alt),
              label: l10n.animatedArtworkMenuReset,
              onPressed: () => Navigator.of(menuContext).pop('reset'),
            ),
        ],
      ],
    ),
  );
  if (!context.mounted || action == null) return false;
  return runAnimatedArtworkAction(
    context,
    ref,
    action: action,
    target: target,
    title: title,
    artistName: artistName,
    trackCount: trackCount,
  );
}

/// Runs Find or Reset for one album or artist. Shared by the album menu and
/// the artist menu, so both behave the same way. Returns true when the
/// artwork changed.
Future<bool> runAnimatedArtworkAction(
  BuildContext context,
  WidgetRef ref, {
  required String action,
  required AnimatedArtworkRef target,
  required String title,
  required String? artistName,
  int? trackCount,
}) async {
  if (action == 'find') {
    final saved = await showFindAnimatedArtworkSheet(
      context,
      target: target,
      title: title,
      artistName: artistName,
      trackCount: trackCount,
    );
    if (saved == true) _refresh(ref, target);
    return saved == true;
  }
  if (action != 'reset') return false;

  final l10n = context.l10n;
  final outcome = await resetAnimatedVideo(
    store: ref.read(animatedArtworkStoreProvider),
    kind: target.kind,
    key: target.key,
  );
  if (!context.mounted) return false;
  _refresh(ref, target);
  final message = outcome == AnimatedArtworkSaveOutcome.saved
      ? l10n.animatedArtworkResetDone
      : l10n.animatedArtworkSaveFailed;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  return outcome == AnimatedArtworkSaveOutcome.saved;
}

void _refresh(WidgetRef ref, AnimatedArtworkRef target) {
  ref.read(animatedArtworkRevisionProvider.notifier).bump();
  ref.invalidate(animatedArtworkFileProvider(target));
}

/// Search Apple Music for an album or artist and save the video the user
/// picks. Returns true when a video was saved.
Future<bool?> showFindAnimatedArtworkSheet(
  BuildContext context, {
  required AnimatedArtworkRef target,
  required String title,
  required String? artistName,
  int? trackCount,
}) {
  return showAppScrollableBottomSheet<bool>(
    context: context,
    title: context.l10n.animatedArtworkSheetTitle,
    builder: (context, scrollController) => FindAnimatedArtworkSheet(
      target: target,
      title: title,
      artistName: artistName,
      trackCount: trackCount,
      scrollController: scrollController,
    ),
  );
}

class FindAnimatedArtworkSheet extends ConsumerStatefulWidget {
  const FindAnimatedArtworkSheet({
    super.key,
    required this.target,
    required this.title,
    required this.artistName,
    required this.scrollController,
    this.trackCount,
  });

  final AnimatedArtworkRef target;

  /// The album title, or the artist name for an artist.
  final String title;

  /// The album artist for albums; null for artists.
  final String? artistName;
  final int? trackCount;
  final ScrollController scrollController;

  @override
  ConsumerState<FindAnimatedArtworkSheet> createState() =>
      _FindAnimatedArtworkSheetState();
}

class _FindAnimatedArtworkSheetState
    extends ConsumerState<FindAnimatedArtworkSheet> {
  late final _title = TextEditingController(text: widget.title);
  late final _artist = TextEditingController(text: widget.artistName ?? '');
  bool get _isAlbum => widget.target.kind == AnimatedArtworkKind.album;

  List<AppleArtworkCandidate>? _results;
  AppleArtworkCandidate? _chosen;
  AppleMotionVideo? _video;
  String? _previewUrl;
  bool _searching = false;
  bool _busy = false;
  String? _message;

  /// Closed in dispose, so a save that is still downloading stops.
  bool _alive = true;
  int _request = 0;
  final http.Client _http = http.Client();
  late final AppleArtworkClient _api = AppleArtworkClient(client: _http);

  @override
  void dispose() {
    _alive = false;
    _request++;
    _http.close();
    _title.dispose();
    _artist.dispose();
    super.dispose();
  }

  String get _term {
    final title = _title.text.trim();
    final artist = _artist.text.trim();
    if (_isAlbum) return '$title $artist'.trim();
    return title;
  }

  Future<void> _search() async {
    if (_busy) return;
    final l10n = context.l10n;
    final request = ++_request;
    setState(() {
      _searching = true;
      _message = null;
      _chosen = null;
      _video = null;
      _previewUrl = null;
    });
    try {
      final link = await resolveAppleArtworkLink(_api, _term);
      if (!_alive || request != _request) return;
      final results = link != null
          ? [link].where((c) => c.kind == _kindOf(widget.target)).toList()
          : await searchAppleArtwork(
              _api,
              kind: _kindOf(widget.target),
              term: _term,
            );
      if (!_alive || request != _request) return;
      setState(() => _results = results);
    } on AppleArtworkUnavailable catch (error) {
      AppLogger('AnimatedArtwork').w('Catalog search failed: $error');
      if (_alive && request == _request) {
        setState(() => _message = l10n.animatedArtworkSearchFailed);
      }
    } finally {
      if (_alive && request == _request) setState(() => _searching = false);
    }
  }

  Future<void> _choose(AppleArtworkCandidate candidate) async {
    final l10n = context.l10n;
    final request = ++_request;
    setState(() {
      _chosen = candidate;
      _video = null;
      _previewUrl = null;
      _message = null;
      _busy = true;
    });
    try {
      final video = await chooseAppleVideo(_api, candidate);
      if (!_alive || request != _request) return;
      if (video == null) {
        setState(() => _message = l10n.animatedArtworkNoVideo);
        return;
      }
      setState(() {
        _video = video;
        _previewUrl = video.url;
      });
    } on AppleArtworkUnavailable {
      if (_alive && request == _request) {
        setState(() => _message = l10n.animatedArtworkSearchFailed);
      }
    } finally {
      if (_alive && request == _request) setState(() => _busy = false);
    }
  }

  Future<void> _save({
    required Future<AnimatedArtworkSaveOutcome> Function() action,
  }) async {
    if (_busy) return;
    final l10n = context.l10n;
    final locks = ref.read(animatedArtworkLocksProvider);
    final target = widget.target;
    setState(() {
      _busy = true;
      _message = null;
    });
    locks.lock(target.kind, target.key);
    try {
      final outcome = await action();
      if (!mounted) return;
      switch (outcome) {
        case AnimatedArtworkSaveOutcome.saved:
          _refresh(ref, target);
          Navigator.of(context).pop(true);
        case AnimatedArtworkSaveOutcome.superseded:
          setState(() => _message = l10n.animatedArtworkSuperseded);
        case AnimatedArtworkSaveOutcome.kept:
          setState(() => _message = l10n.animatedArtworkSaveFailed);
      }
    } on AnimatedVideoDownloadException catch (error) {
      AppLogger('AnimatedArtwork').w('Video save failed: $error');
      if (!_alive) return;
      setState(() {
        _message = switch (error.failure) {
          AnimatedVideoFailure.tooLarge => l10n.animatedArtworkTooLarge,
          AnimatedVideoFailure.invalidContainer ||
          AnimatedVideoFailure.unsupportedMedia =>
            l10n.animatedArtworkImportFailed,
          _ => l10n.animatedArtworkDownloadFailed,
        };
      });
    } catch (error) {
      AppLogger('AnimatedArtwork').w('Video save failed: $error');
      if (_alive) setState(() => _message = l10n.animatedArtworkSaveFailed);
    } finally {
      locks.unlock(target.kind, target.key);
      if (_alive) setState(() => _busy = false);
    }
  }

  Future<void> _useCatalogVideo() async {
    final candidate = _chosen;
    final video = _video;
    if (candidate == null || video == null) return;
    final target = widget.target;
    await _save(
      action: () => saveCatalogVideo(
        store: ref.read(animatedArtworkStoreProvider),
        client: _http,
        kind: target.kind,
        key: target.key,
        candidate: candidate,
        video: video,
        isCancelled: () => !_alive,
      ),
    );
  }

  Future<void> _pickFile() async {
    if (_busy) return;
    final l10n = context.l10n;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'm4v', 'mov'],
    );
    if (!mounted || result.isEmpty) return;
    final picked = result.single;
    final target = widget.target;
    final length = await picked.length();
    if (!mounted) return;
    if (length == null || length > kAnimatedArtworkMaxBytes) {
      setState(() => _message = l10n.animatedArtworkTooLarge);
      return;
    }
    await _save(
      action: () => saveImportedVideo(
        store: ref.read(animatedArtworkStoreProvider),
        kind: target.kind,
        key: target.key,
        source: picked.readAsByteStream(),
        declaredLength: length,
      ),
    );
  }

  static AppleArtworkKind _kindOf(AnimatedArtworkRef target) =>
      target.kind == AnimatedArtworkKind.album
      ? AppleArtworkKind.album
      : AppleArtworkKind.artist;

  @override
  Widget build(BuildContext context) {
    final chosen = _chosen;
    if (chosen != null) return _buildPreview(chosen);
    return _buildSearch();
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
          controller: _title,
          textInputAction: _isAlbum
              ? TextInputAction.next
              : TextInputAction.search,
          onSubmitted: (_) => _isAlbum ? null : _search(),
          decoration: InputDecoration(
            labelText: _isAlbum
                ? l10n.animatedArtworkFieldTitle
                : l10n.animatedArtworkFieldArtist,
          ),
        ),
        if (_isAlbum) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _artist,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: l10n.animatedArtworkFieldArtist,
            ),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          l10n.animatedArtworkLinkHint,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _searching || _busy ? null : _search,
          child: Text(l10n.animatedArtworkSearch),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickFile,
          icon: const Icon(Icons.video_file_outlined),
          label: Text(l10n.animatedArtworkPickFile),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 12),
        if (_searching)
          const LinearProgressIndicator()
        else if (results != null && results.isEmpty)
          Text(l10n.animatedArtworkNoResults)
        else if (results != null)
          for (final candidate in results)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _StillPreview(url: candidate.previewUrl),
              title: Text(
                candidate.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: candidate.artistName == null
                  ? null
                  : Text(
                      candidate.artistName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              onTap: _busy ? null : () => _choose(candidate),
            ),
      ],
    );
  }

  Widget _buildPreview(AppleArtworkCandidate candidate) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final url = _previewUrl;
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: const BackButtonIcon(),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _chosen = null;
                      _video = null;
                      _previewUrl = null;
                    }),
            ),
            Expanded(
              child: Text(
                candidate.name,
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
            child: url == null
                ? _StillPreview(url: candidate.previewUrl, size: null)
                : AnimatedArtworkVideo(
                    networkUrl: url,
                    fallback: _StillPreview(
                      url: candidate.previewUrl,
                      size: null,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy || _video == null ? null : _useCatalogVideo,
          child: Text(l10n.animatedArtworkUse),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 16),
        Text(
          l10n.animatedArtworkNotice,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// The static still for a result row. Shown in the list and as the fallback
/// behind the preview video; it never animates.
class _StillPreview extends StatelessWidget {
  const _StillPreview({required this.url, this.size = 48});

  final String? url;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final box = size;
    final child = url == null
        ? const Icon(Icons.album_outlined)
        : Image.network(
            url!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(Icons.album_outlined),
          );
    return SizedBox(
      width: box,
      height: box,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: child,
        ),
      ),
    );
  }
}
