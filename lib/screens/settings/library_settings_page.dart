import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sistrum/widgets/app_alert_dialog.dart';
import 'package:sistrum/widgets/app_switch.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/library_scan_failure.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/services/library_database.dart';
import 'package:sistrum/services/library_folder_selection.dart';
import 'package:sistrum/utils/adaptive_layout.dart';
import 'package:sistrum/widgets/duplicate_review_sheet.dart';
import 'package:sistrum/widgets/app_bottom_sheet.dart';
import 'package:sistrum/widgets/settings_group.dart';
import 'package:sistrum/widgets/app_sliver_header.dart';
import 'package:sistrum/screens/settings/metadata_separator_settings_page.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/utils/nav_bar_inset.dart';
import 'package:sistrum/widgets/animation_utils.dart';

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
      context,
      ref,
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
        actions: [
          AppDialogAction(
            isDefault: true,
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.dialogCancel),
          ),
          AppDialogAction(
            filled: true,
            isDestructive: true,
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(context.l10n.dialogClear),
          ),
        ],
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
        actions: [
          AppDialogAction(
            isDefault: true,
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.dialogCancel),
          ),
          AppDialogAction(
            filled: true,
            isDestructive: true,
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(context.l10n.dialogRemove),
          ),
        ],
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
            _AutoScanOption(
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
            _AutoScanOption(
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
            _AutoScanOption(
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
            _AutoScanOption(
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
                return _LibraryHeroCard(
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
                      return _LibrarySourceSettingsItem(
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
                      page: const SistrumSettingsTheme(
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
                      _ScanProgressTile(
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

class _LibrarySourceSettingsItem extends StatelessWidget {
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

  const _LibrarySourceSettingsItem({
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

class _LibraryHeroCard extends StatelessWidget {
  final int itemCount;
  final bool isScanning;
  final bool scanIsFinalizing;
  final bool scanIsPaused;
  final double scanProgress;
  final String? scanCurrentFile;
  final int scanTotalFiles;
  final int scannedFiles;
  final DateTime? lastScannedAt;

  const _LibraryHeroCard({
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

class _ScanProgressTile extends StatelessWidget {
  final bool isFinalizing;
  final bool isPaused;
  final double progress;
  final String? currentFile;
  final int scannedFiles;
  final int totalFiles;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;

  const _ScanProgressTile({
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

class _AutoScanOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _AutoScanOption({
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
