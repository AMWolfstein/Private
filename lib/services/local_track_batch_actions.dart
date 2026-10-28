import 'package:flutter/material.dart';
import 'package:sistrum/widgets/app_alert_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/unified_library_item.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/services/embedded_cover_resolver.dart';
import 'package:sistrum/services/deleted_library_files.dart';
import 'package:sistrum/utils/confirm_and_delete_tracks.dart';
import 'package:sistrum/utils/file_access.dart';

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
  if (confirmed != true || !isActive() || !context.mounted) return;

  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final deletedPaths = <String>{};
  final cueIds = <String>[];
  var deletedCount = 0;
  for (final item in selected) {
    if (isCueBackedRow(item.filePath, item.localItem.format)) {
      // A CUE row shares its backing sheet/audio with sibling tracks; removing
      // the row must never delete those files.
      cueIds.add(item.localItem.id);
      deletedCount++;
      continue;
    }
    final cleanPath = EmbeddedCoverResolver.cleanFilePath(item.filePath);
    if (!await deleteFile(cleanPath)) continue;
    deletedPaths.add(cleanPath);
    deletedCount++;
  }
  await removeDeletedLibraryFileEntries(container, deletedPaths);
  if (cueIds.isNotEmpty) {
    await container.read(localLibraryProvider.notifier).removeItems(cueIds);
  }
  if (!isActive() || !context.mounted) return;
  onComplete();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        trackDeletionResultMessage(
          l10n,
          deleted: deletedCount,
          requested: selected.length,
        ),
      ),
    ),
  );
}
