import 'package:flutter/material.dart';
import 'package:spotiflac_android/widgets/app_alert_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/unified_library_item.dart';
import 'package:spotiflac_android/services/downloaded_embedded_cover_resolver.dart';
import 'package:spotiflac_android/services/deleted_library_files.dart';
import 'package:spotiflac_android/utils/confirm_and_delete_tracks.dart';
import 'package:spotiflac_android/utils/file_access.dart';

/// Confirms, then deletes the files behind [selected] and removes their
/// history or local-index rows. Files that cannot be deleted keep their rows.
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
  var deletedCount = 0;
  for (final item in selected) {
    final cleanPath = DownloadedEmbeddedCoverResolver.cleanFilePath(
      item.filePath,
    );
    if (!await deleteFile(cleanPath)) continue;
    deletedPaths.add(cleanPath);
    deletedCount++;
  }
  await removeDeletedLibraryFileEntries(container, deletedPaths);
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
