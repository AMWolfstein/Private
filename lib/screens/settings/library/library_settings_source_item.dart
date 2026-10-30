import 'package:flutter/material.dart';
import 'package:sistrum/widgets/primitives/app_switch.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/models/library_scan_failure.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';

class LibrarySourceSettingsItem extends StatelessWidget {
  final LocalLibrarySource source;

  /// Files the last finished scan of [source] could not read.
  final LibraryScanFailures? failures;
  final bool isScanning;
  final bool isFinalizing;
  final bool isPaused;
  final int scannedFiles;
  final int totalFiles;
  final double progress;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onScan;
  final VoidCallback onFullScan;
  final VoidCallback onRemove;

  const LibrarySourceSettingsItem({
    super.key,
    required this.source,
    required this.failures,
    required this.isScanning,
    required this.isFinalizing,
    required this.isPaused,
    required this.scannedFiles,
    required this.totalFiles,
    required this.progress,
    required this.onEnabledChanged,
    required this.onScan,
    required this.onFullScan,
    required this.onRemove,
  });

  String _title() {
    final normalized = source.displayName
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    final name = normalized.split('/').last.trim();
    return name.isEmpty ? source.displayName : name;
  }

  String _lastScanned(BuildContext context) {
    final value = source.lastScannedAt;
    if (value == null) return context.l10n.libraryLastScannedNever;
    final now = DateTime.now();
    final diff = now.difference(value);
    if (diff.inMinutes < 1) return context.l10n.timeJustNow;
    if (diff.inHours < 1) return context.l10n.timeMinutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return context.l10n.timeHoursAgo(diff.inHours);
    if (diff.inDays < 7) return context.l10n.dateDaysAgo(diff.inDays);
    return '${value.day}/${value.month}/${value.year}';
  }

  Future<void> _showActions(BuildContext context) async {
    final canScan = source.enabled && source.available && !isScanning;
    final hasFailures = !isScanning && failures?.files.isNotEmpty == true;
    final action = await showAppBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      title: _title(),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetOption(
            enabled: canScan,
            leading: const Icon(Icons.refresh_rounded),
            title: Text(context.l10n.libraryScan),
            subtitle: Text(context.l10n.libraryScanSubtitle),
            onTap: canScan ? () => Navigator.pop(context, 'scan') : null,
          ),
          AppSheetOption(
            enabled: canScan,
            leading: const Icon(Icons.sync_rounded),
            title: Text(context.l10n.libraryForceFullScan),
            subtitle: Text(context.l10n.libraryForceFullScanSubtitle),
            onTap: canScan ? () => Navigator.pop(context, 'full_scan') : null,
          ),
          if (hasFailures)
            AppSheetOption(
              leading: const Icon(Icons.report_outlined),
              title: Text(context.l10n.libraryUnreadableFilesTitle),
              subtitle: Text(context.l10n.libraryUnreadableFilesAction),
              onTap: () => Navigator.pop(context, 'failures'),
            ),
          AppSheetOption(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              context.l10n.libraryRemoveFolder,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () => Navigator.pop(context, 'remove'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'scan':
        onScan();
      case 'full_scan':
        onFullScan();
      case 'failures':
        await _showFailures(context, failures!);
      case 'remove':
        onRemove();
    }
  }

  Future<void> _showFailures(
    BuildContext context,
    LibraryScanFailures failures,
  ) {
    final files = failures.files;
    final unlisted = failures.count - files.length;
    return showAppBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      title: context.l10n.libraryUnreadableFilesTitle,
      subtitle: context.l10n.libraryUnreadableFilesSubtitle,
      maxHeightFactor: 0.85,
      builder: (context) => CustomScrollView(
        shrinkWrap: true,
        slivers: [
          SliverSettingsGroup(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              return SettingsItem(
                title: file.fileName,
                subtitle: [
                  if (file.folder.isNotEmpty) file.folder,
                  context.friendlyError(file.message),
                ].join('\n'),
                showDivider: index != files.length - 1,
              );
            },
          ),
          if (unlisted > 0)
            SliverPadding(
              padding: const EdgeInsetsDirectional.fromSTEB(32, 12, 32, 0),
              sliver: SliverToBoxAdapter(
                child: Text(
                  context.l10n.libraryUnreadableFilesMore(unlisted),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _title();
    final status = !source.enabled
        ? context.l10n.librarySourceDisabled
        : !source.available
        ? context.l10n.librarySourceOffline
        : isScanning
        ? isFinalizing
              ? context.l10n.libraryScanFinalizing
              : isPaused
              ? context.l10n.libraryScanPaused
              : totalFiles > 0
              ? context.l10n.librarySourceScanCount(
                  scannedFiles,
                  totalFiles,
                  progress.toStringAsFixed(0),
                )
              : context.l10n.libraryScanning
        : source.lastScanError?.trim().isNotEmpty == true
        ? context.l10n.notifLibraryScanFailed
        : context.l10n.librarySourceReady;
    final pathLine = source.displayName == title ? null : source.displayName;
    final details = [
      status,
      context.l10n.libraryTracksUnit(source.trackCount),
      context.l10n.libraryLastScanned(_lastScanned(context)),
    ].join(' · ');

    return SettingsItem(
      icon: source.isRemovable ? Icons.usb_rounded : Icons.folder_outlined,
      title: title,
      titleTrailing: source.isRemovable
          ? Tooltip(
              message: context.l10n.libraryExternalStorage,
              child: const Icon(Icons.sd_storage_outlined, size: 16),
            )
          : null,
      subtitle: [
        ?pathLine,
        details,
        if (!isScanning && source.lastScanError?.trim().isNotEmpty == true)
          context.friendlyError(source.lastScanError!)
        else if (!isScanning && failures != null)
          context.l10n.libraryUnreadableFiles(failures!.count),
      ].join('\n'),
      onTap: () => _showActions(context),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isScanning)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _AnimatedScanCount(
                count: scannedFiles,
                progress: progress,
                determinate: totalFiles > 0 && !isFinalizing,
              ),
            ),
          AppSwitch(
            adaptive: true,
            semanticLabel: title,
            value: source.enabled,
            onChanged: onEnabledChanged,
          ),
        ],
      ),
    );
  }
}

class _AnimatedScanCount extends StatelessWidget {
  final int count;
  final double progress;
  final bool determinate;

  const _AnimatedScanCount({
    required this.count,
    required this.progress,
    required this.determinate,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 42,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              value: determinate ? (progress / 100).clamp(0.0, 1.0) : null,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(height: 2),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: count.toDouble()),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            builder: (context, value, _) => Text(
              value.round().toString(),
              maxLines: 1,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
