import 'package:flutter/material.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/services/deleted_library_files.dart';
import 'package:sistrum/widgets/app_alert_dialog.dart';

String trackDeletionResultMessage(
  AppLocalizations l10n, {
  required int deleted,
  required int requested,
}) => [
  if (deleted > 0 || requested == 0) l10n.snackbarDeletedTracks(deleted),
  if (deleted < requested) l10n.snackbarDeleteTracksFailed(requested - deleted),
].join('\n');

/// Shows a delete-confirmation dialog, runs [deleteItems] for the confirmed
/// IDs, then shows a "deleted N tracks" snackbar. [onExitSelectionMode] runs
/// after the deletion if the screen is still open.
///
/// The destructive policy (CUE protection, physical deletion, index cleanup)
/// belongs to [deleteItems]; this helper only owns the confirmation, the
/// selection exit and the result message. Returns the deletion outcome, or null
/// if the user cancelled the dialog.
Future<DeletedLibraryTracks?> confirmAndDeleteTracks({
  required BuildContext context,
  required List<String> ids,
  required Future<DeletedLibraryTracks> Function(List<String> ids) deleteItems,
  required VoidCallback onExitSelectionMode,
}) async {
  final confirmed = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => AppAlertDialog(
      title: Text(context.l10n.collectionDeleteSelected),
      content: Text(context.l10n.collectionDeleteMessage(ids.length)),
      actions: [
        AppDialogAction(
          isDefault: true,
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(context.l10n.dialogCancel),
        ),
        AppDialogAction(
          filled: true,
          isDestructive: true,
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          child: Text(context.l10n.dialogDelete),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return null;

  final result = await deleteItems(ids);

  if (context.mounted) {
    onExitSelectionMode();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          trackDeletionResultMessage(
            context.l10n,
            deleted: result.deletedCount,
            requested: ids.length,
          ),
        ),
      ),
    );
  }

  return result;
}
