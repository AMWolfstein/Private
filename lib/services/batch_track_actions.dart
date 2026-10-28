import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/unified_library_item.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/services/library/library_database.dart';
import 'package:sistrum/services/replaygain_service.dart';
import 'package:sistrum/utils/file_access.dart';
import 'package:sistrum/utils/logger.dart';
import 'package:sistrum/widgets/app_alert_dialog.dart';
import 'package:sistrum/widgets/batch_progress_dialog.dart';

final _batchActionsLog = AppLogger('BatchActions');

/// Adds or removes ReplayGain tags for [selectedItems].
///
/// [onConfirmOpen] / [onConfirmClosed] let the caller hide and restore any
/// selection UI around the confirmation dialog; [onConfirmClosed] receives
/// whether the user confirmed.
///
/// Returns whether at least one file changed, so callers can skip refreshes
/// after a cancelled or failed batch.
Future<bool> runBatchReplayGain(
  BuildContext sourceContext,
  List<UnifiedLibraryItem> selectedItems, {
  required VoidCallback onExitSelectionMode,
  bool remove = false,
  VoidCallback? onConfirmOpen,
  Future<void> Function(bool confirmed)? onConfirmClosed,
}) async {
  final items = selectedItems
      .where((item) => !isCueVirtualPath(item.filePath))
      .toList(growable: false);
  if (items.isEmpty) return false;

  final container = ProviderScope.containerOf(sourceContext, listen: false);
  // The selection overlay can disappear when opening the confirmation dialog.
  final context = Navigator.of(sourceContext, rootNavigator: true).context;

  onConfirmOpen?.call();

  final confirmed = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => AppAlertDialog(
      title: Text(
        remove
            ? ctx.l10n.trackRemoveReplayGain
            : ctx.l10n.replayGainBatchConfirmTitle,
      ),
      content: Text(
        remove
            ? ctx.l10n.replayGainRemoveConfirmMessage(items.length)
            : ctx.l10n.replayGainBatchConfirmMessage(items.length),
      ),
      actions: [
        AppDialogAction(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ctx.l10n.dialogCancel),
        ),
        AppDialogAction(
          filled: true,
          isDefault: true,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            remove
                ? ctx.l10n.trackRemoveReplayGain
                : ctx.l10n.replayGainBatchConfirmTitle,
          ),
        ),
      ],
    ),
  );

  await onConfirmClosed?.call(confirmed == true);

  if (confirmed != true || !context.mounted) return false;

  var cancelled = false;
  int successCount = 0;
  var unsupportedDecoder = false;
  final total = items.length;

  late final VoidCallback dismissProgress;
  dismissProgress = BatchProgressDialog.show(
    context: context,
    title: remove
        ? context.l10n.replayGainRemoving
        : context.l10n.replayGainBatchAnalyzing,
    total: total,
    icon: Icons.graphic_eq,
    onCancel: () {
      cancelled = true;
      dismissProgress();
    },
  );

  for (int i = 0; i < total; i++) {
    if (!context.mounted || cancelled) break;
    final item = items[i];
    BatchProgressDialog.update(current: i + 1, detail: item.trackName);
    try {
      final ok = remove
          ? await ReplayGainService.removeFromFile(item.filePath)
          : await ReplayGainService.applyToFile(
              item.filePath,
              onUnsupportedDecoder: () => unsupportedDecoder = true,
            );
      if (ok) {
        successCount++;
        try {
          await LibraryDatabase.instance.updateAudioMetadata(
            item.localItem.id,
            hasReplayGain: !remove,
          );
        } catch (e) {
          _batchActionsLog.w('Could not refresh ReplayGain availability: $e');
        }
      } else {
        _batchActionsLog.w('ReplayGain did not change ${item.filePath}');
      }
    } catch (error, stackTrace) {
      _batchActionsLog.e(
        'ReplayGain failed for ${item.filePath}',
        error,
        stackTrace,
      );
    }
  }

  onExitSelectionMode();

  if (successCount > 0 && context.mounted) {
    await container.read(localLibraryProvider.notifier).reloadFromStorage();
  }

  if (!context.mounted) return successCount > 0;
  if (!cancelled) {
    dismissProgress();
  }
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        [
          remove
              ? context.l10n.replayGainRemoveBatchSuccess(successCount, total)
              : context.l10n.replayGainBatchSuccess(successCount, total),
          if (unsupportedDecoder) context.l10n.replayGainUnsupportedDecoder,
        ].join('\n'),
      ),
    ),
  );
  return successCount > 0;
}
