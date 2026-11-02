import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/library/library_database_provider.dart';
import 'package:sistrum/services/native/media_file_bridge.dart';
import 'package:sistrum/services/lyrics/lyrics_matching.dart'
    show normalizeTitle;
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/services/lyrics/lyrics_fetch_controller.dart';
import 'package:sistrum/services/lyrics/lyrics_timing_store.dart';
import 'package:sistrum/services/lyrics/online_lyrics_search.dart';
import 'package:sistrum/utils/layout/nav_bar_inset.dart';
import 'package:sistrum/widgets/lyrics/fetch_lyrics_action.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/utils/logging/logger.dart';

final _log = AppLogger('MissingLyrics');

/// One song the list needs to show, with its last known lyrics timing.
class _SongRow {
  _SongRow(this.item, this.timing);

  final LocalLibraryItem item;

  /// Null means the file has no lyrics at all.
  final LyricsTiming? timing;
}

/// Lists local songs whose files lack word-synced or line-synced lyrics.
/// Timing is read from each file once and remembered; a changed file is read
/// again. Songs with no lyrics need no file read at all.
class MissingLyricsPage extends ConsumerStatefulWidget {
  const MissingLyricsPage({super.key});

  @override
  ConsumerState<MissingLyricsPage> createState() => _MissingLyricsPageState();
}

class _MissingLyricsPageState extends ConsumerState<MissingLyricsPage> {
  final _rows = <_SongRow>[];
  int _checked = 0;
  int _total = 0;
  bool _loading = true;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final state = ref.read(lyricsTimingStateProvider);
      final db = ref.read(libraryDatabaseProvider);
      final items = (await db.listVisibleSongs())
          .map(LocalLibraryItem.fromJson)
          .toList();
      final records = await state.readAll();
      if (_disposed) return;

      final unknown = <LocalLibraryItem>[];
      setState(() => _total = items.length);
      for (final item in items) {
        final fingerprint = lyricsFingerprint(item.filePath, item.fileModTime);
        final record = records[item.id];
        if (record != null && record.fingerprint == fingerprint) {
          _addIfMissing(item, record.timing);
        } else if (!item.hasLyrics) {
          await state.put(
            item.id,
            LyricsTimingRecord(fingerprint: fingerprint, timing: null),
          );
          _addIfMissing(item, null);
        } else {
          unknown.add(item);
        }
      }
      if (!_disposed) setState(() => _checked = items.length - unknown.length);

      for (final item in unknown) {
        if (_disposed) return;
        final timing = await _readTiming(item);
        await state.put(
          item.id,
          LyricsTimingRecord(
            fingerprint: lyricsFingerprint(item.filePath, item.fileModTime),
            timing: timing,
          ),
        );
        if (_disposed) return;
        setState(() {
          _checked++;
          _addIfMissing(item, timing);
        });
      }
    } catch (error) {
      _log.w('Could not list songs without synced lyrics: $error');
    } finally {
      if (!_disposed) setState(() => _loading = false);
    }
  }

  /// Reads the lyrics a file carries and classifies them. A file that cannot
  /// be read counts as having no lyrics, so it is listed rather than hidden.
  Future<LyricsTiming?> _readTiming(LocalLibraryItem item) async {
    try {
      final tags = await MediaFileBridge.readFileMetadata(item.filePath);
      final text = tags['lyrics']?.toString() ?? '';
      if (text.trim().isEmpty) return null;
      return LyricsTiming.detect(text);
    } catch (error) {
      _log.w('Could not read lyrics timing: $error');
      return null;
    }
  }

  void _addIfMissing(LocalLibraryItem item, LyricsTiming? timing) {
    if (timing == LyricsTiming.wordSynced ||
        timing == LyricsTiming.lineSynced) {
      return;
    }
    _rows.add(_SongRow(item, timing));
    _rows.sort(
      (a, b) => normalizeTitle(
        a.item.trackName,
      ).compareTo(normalizeTitle(b.item.trackName)),
    );
  }

  Future<void> _fetch(_SongRow row) async {
    final report = await runFetchLyricsAction(context, ref, row.item);
    if (!mounted || report == null) return;
    final timing = report.timing;
    if (report.outcome == LyricsFetchOutcome.saved &&
        (timing == LyricsTiming.wordSynced ||
            timing == LyricsTiming.lineSynced)) {
      setState(() => _rows.remove(row));
    } else if (report.outcome == LyricsFetchOutcome.saved) {
      setState(() {
        _rows[_rows.indexOf(row)] = _SongRow(row.item, timing);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          AppSliverHeader.page(title: l10n.lyricsMissingTitle),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                l10n.lyricsMissingDescription,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          if (_loading && _total > 0 && _checked < _total)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(
                  value: _total == 0 ? null : _checked / _total,
                ),
              ),
            ),
          if (_loading && _checked < _total)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.lyricsMissingChecking(_checked, _total),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          if (!_loading && _rows.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.lyricsMissingEmpty),
              ),
            ),
          SliverList.builder(
            itemCount: _rows.length,
            itemBuilder: (context, index) {
              final row = _rows[index];
              return ListTile(
                title: Text(
                  row.item.trackName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${row.item.artistName} · ${row.timing == null ? l10n.lyricsMissingStatusNone : l10n.lyricsMissingStatusPlain}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: TextButton(
                  onPressed: () => _fetch(row),
                  child: Text(l10n.lyricsFetchMenu),
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
          const NavBarSliverSpacer(),
        ],
      ),
    );
  }
}
