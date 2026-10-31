import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/providers/library/local_library_provider.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/services/library/scan/library_folder_selection.dart';
import 'package:sistrum/widgets/sheets/duplicate_review_sheet.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';
import 'package:sistrum/widgets/settings/settings_chips_and_cards.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/screens/settings/library/metadata_separator_settings_page.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/utils/layout/nav_bar_inset.dart';
import 'package:sistrum/widgets/animation/animation_utils.dart';
import 'package:sistrum/screens/settings/library/library_settings_scan_widgets.dart';
import 'package:sistrum/screens/settings/library/library_settings_source_item.dart';

part 'library_settings_page_1.dart';

class LibrarySettingsPage extends ConsumerStatefulWidget {
  const LibrarySettingsPage({super.key});

  @override
  ConsumerState<LibrarySettingsPage> createState() =>
      _LibrarySettingsPageState();
}

class _LibrarySettingsPageState extends ConsumerState<LibrarySettingsPage> {
  int _androidSdkVersion = 0;
  bool _hasStoragePermission = false;
  bool _isCleaningMissingFiles = false;

  @override
  void initState() {
    super.initState();
    _initDeviceInfo();
  }

  void _rebuild(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final librarySources = ref.watch(
      localLibraryProvider.select((state) => state.sources),
    );
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          AppSliverHeader.page(title: context.l10n.libraryTitle),

          // Scan snapshots land ~2.5x/s; keep the per-snapshot rebuild scoped
          // to the widgets that actually display scan state instead of the
          // whole settings page.
          SliverToBoxAdapter(
            child: Consumer(
              builder: (context, ref, _) {
                final libraryState = ref.watch(localLibraryProvider);
                return LibraryHeroCard(
                  itemCount: libraryState.totalCount,
                  isScanning: libraryState.isScanning,
                  scanIsFinalizing: libraryState.scanIsFinalizing,
                  scanIsPaused: libraryState.scanIsPaused,
                  scanProgress: libraryState.scanProgress,
                  scanCurrentFile: libraryState.scanCurrentFile,
                  scanTotalFiles: libraryState.scanTotalFiles,
                  scannedFiles: libraryState.scannedFiles,
                  lastScannedAt: libraryState.lastScannedAt,
                );
              },
            ),
          ),

          SliverToBoxAdapter(
            child: SettingsSectionHeader(
              title: context.l10n.libraryScanSettings,
            ),
          ),
          SliverToBoxAdapter(
            child: Consumer(
              builder: (context, ref, _) {
                final status = ref.watch(
                  localLibraryProvider.select(
                    (state) =>
                        (loading: state.isLoading, failed: state.loadFailed),
                  ),
                );
                if (!status.loading && !status.failed) {
                  return const SizedBox.shrink();
                }
                return ListTile(
                  leading: status.loading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.error_outline, color: colorScheme.error),
                  title: Text(
                    status.loading
                        ? context.l10n.libraryLoading
                        : context.l10n.libraryLoadFailed,
                  ),
                  trailing: status.loading
                      ? null
                      : TextButton(
                          onPressed: () => ref
                              .read(localLibraryProvider.notifier)
                              .reloadFromStorage(),
                          child: Text(context.l10n.dialogRetry),
                        ),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsGroup(
              children: [
                for (final source in librarySources)
                  Consumer(
                    key: ValueKey(source.id),
                    builder: (context, ref, _) {
                      final scan = ref.watch(
                        localLibraryProvider.select((state) {
                          final active = state.scanningSourceId == source.id;
                          return (
                            active: active,
                            finalizing: active && state.scanIsFinalizing,
                            paused: active && state.scanIsPaused,
                            scanned: active ? state.scannedFiles : 0,
                            total: active ? state.scanTotalFiles : 0,
                            progress: active ? state.scanProgress : 0.0,
                            failures: state.scanFailures[source.id],
                          );
                        }),
                      );
                      return LibrarySourceSettingsItem(
                        source: source,
                        failures: scan.failures,
                        isScanning: scan.active,
                        isFinalizing: scan.finalizing,
                        isPaused: scan.paused,
                        scannedFiles: scan.scanned,
                        totalFiles: scan.total,
                        progress: scan.progress,
                        onEnabledChanged: (value) => ref
                            .read(localLibraryProvider.notifier)
                            .setSourceEnabled(source.id, value),
                        onScan: () => ref
                            .read(localLibraryProvider.notifier)
                            .startSourceScan(source.id),
                        onFullScan: () => ref
                            .read(localLibraryProvider.notifier)
                            .startSourceScan(source.id, forceFullScan: true),
                        onRemove: () => _removeSource(source),
                      );
                    },
                  ),
                SettingsItem(
                  icon: Icons.create_new_folder_outlined,
                  title: context.l10n.libraryAddFolder,
                  subtitle: librarySources.isEmpty
                      ? context.l10n.libraryFolderHint
                      : context.l10n.libraryAddFolderSubtitle,
                  onTap: _pickLibraryFolder,
                ),
                SettingsSwitchItem(
                  icon: Icons.content_copy_outlined,
                  title: context.l10n.libraryShowDuplicateIndicator,
                  subtitle: settings.localLibraryShowDuplicates
                      ? context.l10n.libraryShowDuplicateIndicatorSubtitle
                      : context.l10n.settingDisabled,
                  value: settings.localLibraryShowDuplicates,
                  onChanged: (value) => ref
                      .read(settingsProvider.notifier)
                      .setLocalLibraryShowDuplicates(value),
                ),
                SettingsItem(
                  icon: Icons.difference_outlined,
                  title: context.l10n.libraryReviewDuplicates,
                  subtitle: context.l10n.libraryReviewDuplicatesSubtitle,
                  onTap: () => DuplicateReviewSheet.show(context),
                ),
                SettingsItem(
                  icon: Icons.autorenew_rounded,
                  title: context.l10n.libraryAutoScan,
                  subtitle: _getAutoScanLabel(
                    context,
                    settings.localLibraryAutoScan,
                  ),
                  onTap: () => _showAutoScanPicker(
                    context,
                    settings.localLibraryAutoScan,
                  ),
                ),
                SettingsItem(
                  icon: Icons.format_list_bulleted,
                  title: context.l10n.metadataSeparators,
                  onTap: () => Navigator.of(context).push(
                    slidePageRoute<void>(
                      page: const AppSettingsTheme(
                        child: MetadataSeparatorSettingsPage(),
                      ),
                    ),
                  ),
                  showDivider: false,
                ),
              ],
            ),
          ),

          SliverToBoxAdapter(
            child: SettingsSectionHeader(title: context.l10n.libraryActions),
          ),
          if (ref.watch(localLibraryProvider.select((s) => s.scanWasCancelled)))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_outlined,
                        color: colorScheme.onTertiaryContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.libraryScanCancelled,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onTertiaryContainer,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              context.l10n.libraryScanCancelledSubtitle,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onTertiaryContainer
                                        .withValues(alpha: 0.8),
                                  ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _startScan,
                        child: Text(context.l10n.dialogRetry),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Consumer(
              builder: (context, ref, _) {
                final libraryState = ref.watch(localLibraryProvider);
                final canCleanup =
                    !_isCleaningMissingFiles &&
                    !libraryState.isScanning &&
                    (libraryState.totalCount > 0 || librarySources.isNotEmpty);
                return SettingsGroup(
                  children: [
                    if (libraryState.isScanning)
                      ScanProgressTile(
                        isFinalizing: libraryState.scanIsFinalizing,
                        isPaused: libraryState.scanIsPaused,
                        progress: libraryState.scanProgress,
                        currentFile: libraryState.scanCurrentFile,
                        scannedFiles: libraryState.scannedFiles,
                        totalFiles: libraryState.scanTotalFiles,
                        onPause: _pauseScan,
                        onResume: _resumeScan,
                        onCancel: _cancelScan,
                      )
                    else ...[
                      Opacity(
                        opacity: librarySources.isNotEmpty ? 1.0 : 0.5,
                        child: SettingsItem(
                          icon: Icons.refresh,
                          title: context.l10n.libraryScan,
                          subtitle: librarySources.isEmpty
                              ? context.l10n.libraryScanSelectFolderFirst
                              : context.l10n.libraryScanSubtitle,
                          onTap: librarySources.isNotEmpty ? _startScan : null,
                        ),
                      ),
                      Opacity(
                        opacity: librarySources.isNotEmpty ? 1.0 : 0.5,
                        child: SettingsItem(
                          icon: Icons.sync,
                          title: context.l10n.libraryForceFullScan,
                          subtitle: context.l10n.libraryForceFullScanSubtitle,
                          onTap: librarySources.isNotEmpty
                              ? () => _startScan(forceFullScan: true)
                              : null,
                        ),
                      ),
                    ],
                    Opacity(
                      opacity: canCleanup || _isCleaningMissingFiles
                          ? 1.0
                          : 0.5,
                      child: SettingsItem(
                        icon: Icons.cleaning_services_outlined,
                        title: context.l10n.libraryCleanupMissingFiles,
                        subtitle:
                            context.l10n.libraryCleanupMissingFilesSubtitle,
                        trailing: _isCleaningMissingFiles
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                        onTap: canCleanup ? _cleanupMissingFiles : null,
                      ),
                    ),
                    Opacity(
                      opacity: libraryState.totalCount > 0 ? 1.0 : 0.5,
                      child: SettingsItem(
                        icon: Icons.delete_outline,
                        title: context.l10n.libraryClear,
                        subtitle: context.l10n.libraryClearSubtitle,
                        onTap: libraryState.totalCount > 0
                            ? _clearLibrary
                            : null,
                        showDivider: false,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          SliverToBoxAdapter(
            child: SettingsInfoCard(
              glass: true,
              icon: Icons.info_outline,
              title: context.l10n.libraryAbout,
              message: context.l10n.libraryAboutDescription,
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
          const NavBarSliverSpacer(),
        ],
      ),
    );
  }
}
