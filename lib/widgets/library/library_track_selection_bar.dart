import 'package:flutter/material.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/widgets/primitives/app_action_button.dart';
import 'package:sistrum/widgets/selection/selection_bottom_bar.dart';

/// Shared Library toolbar for playlist/queue actions and audio file operations.
class LibraryTrackSelectionBar extends StatelessWidget {
  const LibraryTrackSelectionBar({
    super.key,
    required this.selectedCount,
    required this.allSelected,
    required this.onClose,
    required this.onToggleSelectAll,
    required this.bottomPadding,
    required this.onDelete,
    this.playbackActions,
  });

  final int selectedCount;
  final bool allSelected;
  final VoidCallback onClose;
  final VoidCallback onToggleSelectAll;
  final double bottomPadding;
  final VoidCallback onDelete;
  final Widget? playbackActions;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasSelection = selectedCount > 0;
    return SelectionBottomBar(
      selectedCount: selectedCount,
      allSelected: allSelected,
      onClose: onClose,
      onToggleSelectAll: onToggleSelectAll,
      bottomPadding: bottomPadding,
      children: [
        ?playbackActions,
        if (playbackActions != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(context.l10n.trackEditMetadata),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: AppActionButton(
            isDestructive: true,
            onPressed: hasSelection ? onDelete : null,
            icon: const Icon(Icons.delete_outline),
            label: Text(
              hasSelection
                  ? context.l10n.selectionDeleteTracksCount(selectedCount)
                  : context.l10n.selectionSelectToDelete,
            ),
            style: FilledButton.styleFrom(
              backgroundColor: hasSelection
                  ? colorScheme.error
                  : colorScheme.surfaceContainerHighest,
              foregroundColor: hasSelection
                  ? colorScheme.onError
                  : colorScheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
