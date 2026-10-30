import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
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

  Future<void> _initDeviceInfo() async {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkVersion = androidInfo.version.sdkInt;

      if (mounted) {
        setState(() {
          _androidSdkVersion = sdkVersion;
          _hasStoragePermission = sdkVersion >= 29;
        });
        if (sdkVersion < 29) {
          final hasPermission = await Permission.storage.isGranted;
          if (mounted) {
            setState(() => _hasStoragePermission = hasPermission);
          }
        }
      }
    } else {
      setState(() => _hasStoragePermission = true);
    }
  }

  Future<bool> _requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    if (_androidSdkVersion >= 29) return true;

    final status = await Permission.storage.request();

    if (status.isGranted) {
      if (mounted) setState(() => _hasStoragePermission = true);
      return true;
    } else if (status.isPermanentlyDenied) {
      if (mounted) {
        final shouldOpen = await showAppDialog<bool>(
          context: context,
          builder: (context) => AppAlertDialog(
            title: Text(context.l10n.libraryStorageAccessRequired),
            content: Text(context.l10n.libraryStorageAccessMessage),
            actions: [
              AppDialogAction(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.dialogCancel),
              ),
              AppDialogAction(
                filled: true,
                isDefault: true,
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.l10n.setupOpenSettings),
              ),
            ],
          ),
        );
        if (shouldOpen == true) {
          await openAppSettings();
        }
      }
    }
    return false;
  }

  Future<void> _pickLibraryFolder() async {
    try {
      await _pickLibraryFolderInternal();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.snackbarError(context.friendlyError(error)),
          ),
        ),
      );
    }
  }

  Future<void> _pickLibraryFolderInternal() async {
    // Older Android needs storage permission; Android 10+ and iOS pick a
    // folder through the scoped picker.
    if (!_hasStoragePermission) {
      final granted = await _requestStoragePermission();
      if (!granted || !mounted) return;
    }
    final messenger = ScaffoldMessenger.of(context);
    await selectLibraryFolder(
      ref.read(localLibraryProvider.notifier),
      androidSdkVersion: _androidSdkVersion,
      onFailure: (message) {
        if (mounted) {
          messenger.showSnackBar(SnackBar(content: Text(message)));
        }
      },
    );
  }

  Future<void> _startScan({bool forceFullScan = false}) async {
    final sources = ref.read(localLibraryProvider).sources;
    if (sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.libraryScanSelectFolderFirst)),
      );
      return;
    }
    try {
      await ref
          .read(localLibraryProvider.notifier)
          .scanAllSources(forceFullScan: forceFullScan);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.snackbarError(context.friendlyError(error)),
          ),
        ),
      );
    }
  }

  Future<void> _cancelScan() async {
    await ref.read(localLibraryProvider.notifier).cancelScan();
  }

  Future<void> _pauseScan() async {
    await ref.read(localLibraryProvider.notifier).pauseScan();
  }

  Future<void> _resumeScan() async {
    await ref.read(localLibraryProvider.notifier).resumeScan();
  }

  Future<void> _clearLibrary() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(context.l10n.libraryClearConfirmTitle),
        content: Text(context.l10n.libraryClearConfirmMessage),
        actions: appDestructiveConfirmActions(
          context,
          cancelLabel: context.l10n.dialogCancel,
          confirmLabel: context.l10n.dialogClear,
          cancelIsDefault: true,
        ),
      ),
    );

    if (confirmed == true) {
      await ref.read(localLibraryProvider.notifier).clearLibrary();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.libraryCleared)));
      }
    }
  }

  Future<void> _cleanupMissingFiles() async {
    if (_isCleaningMissingFiles || ref.read(localLibraryProvider).isScanning) {
      return;
    }
    final library = ref.read(localLibraryProvider.notifier);
    setState(() => _isCleaningMissingFiles = true);
    try {
      final missingLibraryEntries = await library.cleanupMissingFiles();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.libraryRemovedMissingFiles(missingLibraryEntries),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.snackbarError(context.friendlyError(error)),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isCleaningMissingFiles = false);
    }
  }

  Future<void> _removeSource(LocalLibrarySource source) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(context.l10n.libraryRemoveFolder),
        content: Text(context.l10n.libraryRemoveFolderMessage),
        actions: appDestructiveConfirmActions(
          context,
          cancelLabel: context.l10n.dialogCancel,
          confirmLabel: context.l10n.dialogRemove,
          cancelIsDefault: true,
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(localLibraryProvider.notifier).removeSource(source.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.snackbarError(context.friendlyError(error)),
          ),
        ),
      );
      return;
    }
  }

  String _getAutoScanLabel(BuildContext context, String mode) {
    switch (mode) {
      case 'on_open':
        return context.l10n.libraryAutoScanOnOpen;
      case 'daily':
        return context.l10n.libraryAutoScanDaily;
      case 'weekly':
        return context.l10n.libraryAutoScanWeekly;
      default:
        return context.l10n.libraryAutoScanOff;
    }
  }

  void _showAutoScanPicker(BuildContext context, String current) {
    showAppScrollableBottomSheet<void>(
      context: context,
      title: context.l10n.libraryAutoScan,
      subtitle: context.l10n.libraryAutoScanSubtitle,
      builder: (context, controller) => SingleChildScrollView(
        controller: controller,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AutoScanOption(
              icon: Icons.block,
              title: context.l10n.libraryAutoScanOff,
              selected: current == 'off',
              onTap: () {
                ref
                    .read(settingsProvider.notifier)
                    .setLocalLibraryAutoScan('off');
                Navigator.pop(context);
              },
            ),
            AutoScanOption(
              icon: Icons.open_in_new,
              title: context.l10n.libraryAutoScanOnOpen,
              selected: current == 'on_open',
              onTap: () {
                ref
                    .read(settingsProvider.notifier)
                    .setLocalLibraryAutoScan('on_open');
                Navigator.pop(context);
              },
            ),
            AutoScanOption(
              icon: Icons.today,
              title: context.l10n.libraryAutoScanDaily,
              selected: current == 'daily',
              onTap: () {
                ref
                    .read(settingsProvider.notifier)
                    .setLocalLibraryAutoScan('daily');
                Navigator.pop(context);
              },
            ),
            AutoScanOption(
              icon: Icons.date_range,
              title: context.l10n.libraryAutoScanWeekly,
              selected: current == 'weekly',
              onTap: () {
                ref
                    .read(settingsProvider.notifier)
                    .setLocalLibraryAutoScan('weekly');
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

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
