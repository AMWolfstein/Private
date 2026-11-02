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
import 'package:sistrum/services/lyrics/lyrics_fetch_controller.dart';
import 'package:sistrum/services/lyrics/lyrics_timing_store.dart';
import 'package:sistrum/services/lyrics/online_lyrics_providers.dart';
import 'package:sistrum/services/lyrics/online_lyrics_search.dart';
import 'package:sistrum/utils/logging/logger.dart';

final _log = AppLogger('FetchLyrics');

/// Where lyrics timing per song is remembered. One instance for the app.
final lyricsTimingStateProvider = Provider<LyricsTimingState>(
  (ref) => LyricsTimingDb(),
);

/// Runs Fetch lyrics for one song from the user's tap. Asks before replacing
/// lyrics or using plain text, reports the outcome, and returns the report.
Future<LyricsFetchReport?> runFetchLyricsAction(
  BuildContext context,
  WidgetRef ref,
  LocalLibraryItem item,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final client = http.Client();
  var cancelled = false;

  final controller = LyricsFetchController(
    search: () => OnlineLyricsSearch(onlineLyricsProviders(client)),
    store: MetadataEmbeddedLyricsStore(
      refreshIndex: (changed) => _refreshLibrary(ref, changed),
    ),
    prompts: _DialogLyricsPrompts(context),
    timings: ref.read(lyricsTimingStateProvider),
  );

  messenger.hideCurrentSnackBar();
  final searching = messenger.showSnackBar(
    SnackBar(
      content: Text(l10n.lyricsFetchSearching),
      duration: const Duration(minutes: 5),
      action: SnackBarAction(
        label: l10n.lyricsFetchCancel,
        onPressed: () => cancelled = true,
      ),
    ),
  );

  LyricsFetchReport? report;
  try {
    report = await controller.run(item, isCancelled: () => cancelled);
  } catch (error) {
    _log.w('Fetch lyrics failed: $error');
  } finally {
    client.close();
    searching.close();
  }

  if (!context.mounted) return report;
  messenger.hideCurrentSnackBar();
  final message = report == null
      ? l10n.lyricsFetchFailed
      : _messageFor(l10n, report);
  if (message != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
  return report;
}

String? _messageFor(AppLocalizations strings, LyricsFetchReport report) {
  final unreachable = report.failedProviders.isEmpty
      ? null
      : strings.lyricsFetchUnreachable(report.failedProviders.join(', '));
  final main = switch (report.outcome) {
    LyricsFetchOutcome.saved =>
      report.timing == LyricsTiming.plain
          ? strings.lyricsFetchSavedPlain
          : strings.lyricsFetchSavedSynced,
    LyricsFetchOutcome.keptExisting => strings.lyricsFetchKept,
    LyricsFetchOutcome.declinedPlain => strings.lyricsFetchDeclinedPlain,
    LyricsFetchOutcome.notFound => strings.lyricsFetchNotFound,
    LyricsFetchOutcome.writeFailed => strings.lyricsFetchWriteFailed,
    LyricsFetchOutcome.cancelled => null,
  };
  if (main == null) return null;
  // A failed source matters only when nothing was saved.
  if (unreachable != null && report.outcome != LyricsFetchOutcome.saved) {
    return '$main\n$unreachable';
  }
  return main;
}

Future<void> _refreshLibrary(WidgetRef ref, LocalLibraryItem item) async {
  final index = await MetadataIndexReconciler(
    upsert: ref.read(libraryDatabaseProvider).upsert,
  ).reconcile(item);
  ref.read(libraryTagCreditsCacheProvider).invalidate();
  await ref.read(localLibraryProvider.notifier).reloadFromStorage();
  if (!index.indexed) {
    throw StateError('index not refreshed after saving lyrics');
  }
}

class _DialogLyricsPrompts implements LyricsFetchPrompts {
  _DialogLyricsPrompts(this._context);

  final BuildContext _context;

  @override
  Future<bool> confirmReplaceExisting() => _ask(
    (l10n) => l10n.lyricsFetchReplaceTitle,
    (l10n) => l10n.lyricsFetchReplaceBody,
  );

  @override
  Future<bool> confirmPlainLyrics() => _ask(
    (l10n) => l10n.lyricsFetchPlainTitle,
    (l10n) => l10n.lyricsFetchPlainBody,
  );

  Future<bool> _ask(
    String Function(AppLocalizations) title,
    String Function(AppLocalizations) body,
  ) async {
    if (!_context.mounted) return false;
    final l10n = _context.l10n;
    final answer = await showDialog<bool>(
      context: _context,
      useRootNavigator: true,
      builder: (dialog) => AlertDialog(
        title: Text(title(l10n)),
        content: Text(body(l10n)),
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
}
