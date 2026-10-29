import 'package:flutter/material.dart';
import 'package:sistrum/utils/log_entry.dart';

class LogEntryTile extends StatelessWidget {
  final LogEntry entry;
  final Color levelColor;
  final bool showDivider;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const LogEntryTile({
    super.key,
    required this.entry,
    required this.levelColor,
    this.showDivider = true,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isError = entry.level == 'ERROR' || entry.level == 'FATAL';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          container: true,
          selected: selected,
          onTap: selectionMode ? onTap : null,
          onLongPress: onLongPress,
          child: InkWell(
            excludeFromSemantics: true,
            onTap: selectionMode ? onTap : null,
            onLongPress: onLongPress,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                    : isError
                    ? colorScheme.errorContainer.withValues(alpha: 0.2)
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        entry.formattedTime,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: levelColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          entry.level,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: levelColor,
                          ),
                        ),
                      ),
                      if (entry.isFromGo) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Native',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.tag,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (selectionMode) ...[
                        const SizedBox(width: 8),
                        Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 20,
                          color: selected
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    entry.previewMessage,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: colorScheme.onSurface,
                      height: 1.4,
                    ),
                  ),
                  if (entry.previewError != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      entry.previewError!,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: colorScheme.error,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 20,
            endIndent: 20,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
      ],
    );
  }
}
