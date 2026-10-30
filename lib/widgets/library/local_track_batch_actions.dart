import 'package:flutter/material.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/unified_library_item.dart';
import 'package:sistrum/services/library/scan/deleted_library_files.dart';
import 'package:sistrum/widgets/selection/confirm_and_delete_tracks.dart';
import 'package:sistrum/providers/local_library_provider.dart';

/// Confirms, then deletes the files behind [selected] and removes their
/// local-index rows. Files that cannot be deleted keep their rows.
Future<void> deleteLibraryTracks(
  BuildContext context,
  WidgetRef ref,
  List<UnifiedLibraryItem> selected, {
  required bool Function() isActive,
  required VoidCallback onComplete,
}) async {
  if (selected.isEmpty) return;
  final confirmed = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => AppAlertDialog(
      title: Text(context.l10n.dialogDeleteSelectedTitle),
      content: Text(context.l10n.dialogDeleteSelectedMessage(selected.length)),
      actions: appDestructiveConfirmActions(
        ctx,
        cancelLabel: context.l10n.dialogCancel,
        confirmLabel: context.l10n.dialogDelete,
        cancelIsDefault: true,
      ),
    ),
  );
  if (confirmed != true || !isActive() || !context.mounted) return;

  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final result = await deleteLocalLibraryTracks(
    container.read(localLibraryProvider.notifier),
    [for (final item in selected) item.localItem],
  );
  if (!isActive() || !context.mounted) return;
  onComplete();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        trackDeletionResultMessage(
          l10n,
          deleted: result.deletedCount,
          requested: selected.length,
        ),
      ),
    ),
  );
}
