import 'package:flutter/material.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/utils/layout/adaptive_layout.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';

class LibraryHeroCard extends StatelessWidget {
  final int itemCount;
  final bool isScanning;
  final bool scanIsFinalizing;
  final bool scanIsPaused;
  final double scanProgress;
  final String? scanCurrentFile;
  final int scanTotalFiles;
  final int scannedFiles;
  final DateTime? lastScannedAt;

  const LibraryHeroCard({
    super.key,
    required this.itemCount,
    required this.isScanning,
    required this.scanIsFinalizing,
    required this.scanIsPaused,
    required this.scanProgress,
    this.scanCurrentFile,
    required this.scanTotalFiles,
    required this.scannedFiles,
    this.lastScannedAt,
  });

  String _formatLastScanned(BuildContext context) {
    if (lastScannedAt == null) return context.l10n.libraryLastScannedNever;
    final now = DateTime.now();
    final diff = now.difference(lastScannedAt!);

    if (diff.inMinutes < 1) return context.l10n.timeJustNow;
    if (diff.inHours < 1) return context.l10n.timeMinutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return context.l10n.timeHoursAgo(diff.inHours);
    if (diff.inDays < 7) return context.l10n.dateDaysAgo(diff.inDays);

    return '${lastScannedAt!.day}/${lastScannedAt!.month}/${lastScannedAt!.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showIndeterminateProgress =
        isScanning &&
        !scanIsPaused &&
        (scanIsFinalizing ||
            scanTotalFiles <= 0 ||
            (scannedFiles <= 0 && scanProgress <= 0));
    final displayCount = isScanning ? scannedFiles : itemCount;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: 16 + wideListInset(context),
        vertical: 8,
      ),
      constraints: const BoxConstraints(minHeight: 220),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Icon(
              Icons.library_music,
              size: 200,
              color: colorScheme.primary.withValues(alpha: 0.05),
            ),
          ),
          Positioned(
            left: -40,
            bottom: -40,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.secondaryContainer.withValues(alpha: 0.3),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        isScanning
                            ? scanIsPaused
                                  ? Icons.pause_rounded
                                  : Icons.sync
                            : Icons.music_note,
                        color: colorScheme.onPrimaryContainer,
                        size: 32,
                      ),
                    ),
                    const Spacer(),
                    if (isScanning)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: scanIsPaused
                                  ? Icon(
                                      Icons.pause_rounded,
                                      size: 12,
                                      color: colorScheme.onPrimary,
                                    )
                                  : CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colorScheme.onPrimary,
                                    ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              scanIsPaused
                                  ? context.l10n.libraryScanPaused
                                  : context.l10n.libraryScanning,
                              style: TextStyle(
                                color: colorScheme.onPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    displayCount.toString(),
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                      height: 1.0,
                      letterSpacing: -2,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isScanning
                      ? context.l10n.libraryFilesUnit(scannedFiles)
                      : context.l10n.libraryTracksUnit(displayCount),
                  style: TextStyle(
                    fontSize: 16,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                if (isScanning) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: showIndeterminateProgress
                        ? null
                        : scanTotalFiles > 0
                        ? scanProgress / 100
                        : 0,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    scanIsFinalizing
                        ? context.l10n.libraryScanFinalizing
                        : scanTotalFiles > 0
                        ? context.l10n.libraryScanProgress(
                            scanProgress.toStringAsFixed(0),
                            scanTotalFiles,
                          )
                        : scanIsPaused
                        ? context.l10n.libraryScanPaused
                        : context.l10n.libraryScanning,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.8,
                      ),
                    ),
                  ),
                  if (!scanIsFinalizing &&
                      scanCurrentFile != null &&
                      scanCurrentFile!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      scanCurrentFile!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ],
                ] else ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.history,
                        size: 14,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        context.l10n.libraryLastScanned(
                          _formatLastScanned(context),
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ScanProgressTile extends StatelessWidget {
  final bool isFinalizing;
  final bool isPaused;
  final double progress;
  final String? currentFile;
  final int scannedFiles;
  final int totalFiles;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;

  const ScanProgressTile({
    super.key,
    required this.isFinalizing,
    required this.isPaused,
    required this.progress,
    this.currentFile,
    required this.scannedFiles,
    required this.totalFiles,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // A paused bar stays still at its last position instead of animating.
    final showIndeterminateProgress =
        !isPaused &&
        (isFinalizing ||
            totalFiles <= 0 ||
            (scannedFiles <= 0 && progress <= 0));
    final progressValue = totalFiles > 0 ? progress / 100 : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPaused ? Icons.pause_circle_outline : Icons.scanner,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPaused
                          ? context.l10n.libraryScanPaused
                          : context.l10n.libraryScanning,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      isFinalizing
                          ? context.l10n.libraryScanFinalizing
                          : totalFiles > 0
                          ? context.l10n.libraryScanProgress(
                              progress.toStringAsFixed(0),
                              totalFiles,
                            )
                          : context.l10n.libraryScanning,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isFinalizing)
                TextButton(
                  onPressed: isPaused ? onResume : onPause,
                  child: Text(
                    isPaused
                        ? context.l10n.actionResume
                        : context.l10n.actionPause,
                  ),
                ),
              TextButton(
                onPressed: onCancel,
                child: Text(context.l10n.actionCancel),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: showIndeterminateProgress ? null : progressValue,
            backgroundColor: colorScheme.surfaceContainerHighest,
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(4),
          ),
          if (!isFinalizing &&
              currentFile != null &&
              currentFile!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              currentFile!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class AutoScanOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const AutoScanOption({
    super.key,
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppSheetOption.choice(
      leading: Icon(icon),
      title: Text(title),
      selected: selected,
      onTap: onTap,
    );
  }
}
