import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/library/library_database_provider.dart';
import 'package:sistrum/providers/library/library_tag_credits_provider.dart';
import 'package:sistrum/providers/library/local_library_provider.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/services/library/metadata/metadata_index_reconciler.dart';
import 'package:sistrum/services/lyrics/embedded_lyrics_writer.dart';
import 'package:sistrum/services/lyrics/lrc_sidecar_store.dart';
import 'package:sistrum/services/lyrics/lyrics_matching.dart';
import 'package:sistrum/services/lyrics/lyrics_save_actions.dart';
import 'package:sistrum/services/lyrics/lyrics_timing_store.dart';
import 'package:sistrum/services/lyrics/online_lyrics_providers.dart';
import 'package:sistrum/services/lyrics/online_lyrics_search.dart';
import 'package:sistrum/utils/logging/logger.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';

final _log = AppLogger('FindLyrics');

/// Where lyrics timing per song is remembered. One instance for the app.
final lyricsTimingStateProvider = Provider<LyricsTimingState>(
  (ref) => LyricsTimingDb(),
);

/// Opens Find lyrics for [item], with its title, artist, album and duration
/// filled in. Returns the candidate written into the song's file, or null
/// when nothing was written.
Future<OnlineLyricsCandidate?> showFindLyricsSheet(
  BuildContext context,
  LocalLibraryItem item,
) {
  return showAppScrollableBottomSheet<OnlineLyricsCandidate>(
    context: context,
    title: context.l10n.lyricsFindTitle,
    builder: (context, scrollController) =>
        FindLyricsSheet(item: item, scrollController: scrollController),
  );
}

/// Formats seconds as m:ss, or an empty string when unknown.
String _clock(num? seconds, {String fallback = ''}) {
  if (seconds == null || seconds <= 0) return fallback;
  final whole = seconds.round();
  return '${whole ~/ 60}:${(whole % 60).toString().padLeft(2, '0')}';
}

/// Strips timing and metadata tags so the preview reads as lyrics.
String _displayText(String text) => text
    .split('\n')
    .map((line) => line.replaceAll(RegExp(r'\[[^\]]*\]|<[^>]*>'), '').trim())
    .where((line) => line.isNotEmpty)
    .join('\n');

class FindLyricsSheet extends ConsumerStatefulWidget {
  const FindLyricsSheet({
    super.key,
    required this.item,
    required this.scrollController,
  });

  final LocalLibraryItem item;
  final ScrollController scrollController;

  @override
  ConsumerState<FindLyricsSheet> createState() => _FindLyricsSheetState();
}

class _FindLyricsSheetState extends ConsumerState<FindLyricsSheet> {
  late final _title = TextEditingController(text: widget.item.trackName);
  late final _artist = TextEditingController(text: widget.item.artistName);
  late final _album = TextEditingController(text: widget.item.albumName);
  late final _duration = TextEditingController(
    text: _clock(widget.item.duration),
  );

  OnlineLyricsSearchResult? _results;
  bool _searching = false;
  bool _busy = false;
  OnlineLyricsCandidate? _preview;
  String? _message;

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final l10n = context.l10n;
    final title = _title.text.trim();
    final artist = _artist.text.trim();
    if (title.isEmpty) {
      setState(() => _message = l10n.lyricsFindNeedTitle);
      return;
    }
    final album = _album.text.trim();
    // The file's ISRC identifies its recording only while title and artist
    // are the file's own; an edited search is a different request.
    final unchanged =
        title == widget.item.trackName && artist == widget.item.artistName;
    final query = OnlineLyricsQuery(
      title: title,
      artist: artist,
      album: album.isEmpty ? null : album,
      durationSeconds: parseClockSeconds(_duration.text),
      isrc: unchanged ? widget.item.isrc : null,
    );

    setState(() {
      _searching = true;
      _message = null;
      _preview = null;
    });
    final client = http.Client();
    try {
      final result = await OnlineLyricsSearch(
        onlineLyricsProviders(client),
      ).searchAll(query);
      if (!mounted) return;
      setState(() => _results = result);
    } catch (error) {
      _log.w('Find lyrics search failed: $error');
      if (mounted) setState(() => _message = l10n.lyricsFindSearchFailed);
    } finally {
      client.close();
      if (mounted) setState(() => _searching = false);
    }
  }

  LyricsSaveActions _actions() => LyricsSaveActions(
    embedded: MetadataEmbeddedLyricsStore(refreshIndex: _refreshLibrary),
    sidecar: const LrcSidecarStore(),
    timings: ref.read(lyricsTimingStateProvider),
  );

  Future<void> _embed(OnlineLyricsCandidate candidate) async {
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _message = null;
    });
    final outcome = await _actions().embed(
      widget.item,
      candidate,
      confirmReplace: () =>
          _confirm(l10n.lyricsFetchReplaceTitle, l10n.lyricsFetchReplaceBody),
    );
    if (!mounted) return;
    if (outcome == LyricsSaveOutcome.saved) {
      Navigator.of(context).pop(candidate);
      return;
    }
    setState(() {
      _busy = false;
      _message = switch (outcome) {
        LyricsSaveOutcome.failed => l10n.lyricsFindEmbedFailed,
        _ => null,
      };
    });
  }

  Future<void> _download(OnlineLyricsCandidate candidate) async {
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _message = null;
    });
    final outcome = await _actions().downloadLrc(
      widget.item,
      candidate,
      confirmReplace: () => _confirm(
        l10n.lyricsFindReplaceLrcTitle,
        l10n.lyricsFindReplaceLrcBody,
      ),
    );
    if (!mounted) return;
    final name = lrcSidecarPath(
      widget.item.filePath,
    ).split(RegExp(r'[/\\]')).last;
    setState(() {
      _busy = false;
      _message = switch (outcome) {
        LyricsSaveOutcome.saved => l10n.lyricsFindSavedLrc(name),
        LyricsSaveOutcome.unsupported => l10n.lyricsFindLrcUnsupported,
        LyricsSaveOutcome.failed => l10n.lyricsFindLrcFailed,
        _ => null,
      };
    });
  }

  Future<void> _refreshLibrary(LocalLibraryItem item) async {
    final index = await MetadataIndexReconciler(
      upsert: ref.read(libraryDatabaseProvider).upsert,
    ).reconcile(item);
    ref.read(libraryTagCreditsCacheProvider).invalidate();
    await ref.read(localLibraryProvider.notifier).reloadFromStorage();
    if (!index.indexed) {
      throw StateError('index not refreshed after saving lyrics');
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final l10n = context.l10n;
    final answer = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(l10n.lyricsFetchCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(l10n.lyricsFetchOk),
          ),
        ],
      ),
    );
    return answer ?? false;
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
          controller: _title,
          decoration: InputDecoration(labelText: l10n.lyricsFindTitleLabel),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _artist,
          decoration: InputDecoration(labelText: l10n.lyricsFindArtistLabel),
          onSubmitted: (_) => _search(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _album,
          decoration: InputDecoration(labelText: l10n.lyricsFindAlbumLabel),
          onSubmitted: (_) => _search(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _duration,
          decoration: InputDecoration(
            labelText: l10n.lyricsFindDurationLabel,
            hintText: l10n.lyricsFindDurationHint,
          ),
          onSubmitted: (_) => _search(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _searching ? null : _search,
          child: Text(l10n.lyricsFindSearch),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 16),
        if (_searching) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(l10n.lyricsFindSearching, style: theme.textTheme.bodySmall),
        ] else if (results == null)
          Text(
            l10n.lyricsFindIdle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          ..._resultRows(results),
      ],
    );
  }

  List<Widget> _resultRows(OnlineLyricsSearchResult results) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final widgets = <Widget>[];
    for (final timing in LyricsTiming.values) {
      final group = results.withTiming(timing);
      if (group.isEmpty) continue;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(switch (timing) {
            LyricsTiming.wordSynced => l10n.lyricsFindGroupWord,
            LyricsTiming.lineSynced => l10n.lyricsFindGroupLine,
            LyricsTiming.plain => l10n.lyricsFindGroupPlain,
          }, style: theme.textTheme.titleSmall),
        ),
      );
      for (final candidate in group) {
        widgets.add(
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              candidate.title ?? _title.text.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              [
                candidate.artist ?? _artist.text.trim(),
                candidate.provider,
              ].where((part) => part.isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              _clock(candidate.durationSeconds, fallback: '—'),
              style: theme.textTheme.bodySmall,
            ),
            onTap: () => setState(() {
              _preview = candidate;
              _message = null;
            }),
          ),
        );
      }
    }
    if (results.candidates.isEmpty) {
      widgets.add(Text(l10n.lyricsFindNoResults));
    }
    if (results.failedProviders.isNotEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            l10n.lyricsFindFailedSources(results.failedProviders.join(', ')),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _buildPreview(OnlineLyricsCandidate candidate) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final duration = _clock(candidate.durationSeconds);
    final subtitle = [
      candidate.artist ?? _artist.text.trim(),
      candidate.provider,
      if (duration.isNotEmpty) duration,
    ].where((part) => part.isNotEmpty).join(' · ');
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
                candidate.title ?? _title.text.trim(),
                style: theme.textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : () => _embed(candidate),
          child: Text(l10n.lyricsFindEmbed),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy ? null : () => _download(candidate),
          child: Text(l10n.lyricsFindDownload),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 16),
        SelectableText(
          _displayText(candidate.text),
          style: theme.textTheme.bodyLarge,
        ),
      ],
    );
  }
}
