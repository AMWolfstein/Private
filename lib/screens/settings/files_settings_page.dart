import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:spotiflac_android/widgets/app_bottom_sheet.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';

class FilesSettingsPage extends ConsumerStatefulWidget {
  const FilesSettingsPage({super.key});

  @override
  ConsumerState<FilesSettingsPage> createState() => _FilesSettingsPageState();
}

class _FilesSettingsPageState extends ConsumerState<FilesSettingsPage> {
  bool _safAccessLost = false;

  @override
  void initState() {
    super.initState();
    _checkSafAccess();
  }

  Future<void> _checkSafAccess() async {
    if (!Platform.isAndroid) return;
    final settings = ref.read(settingsProvider);
    if (settings.storageMode != 'saf' || settings.downloadTreeUri.isEmpty) {
      if (mounted && _safAccessLost) setState(() => _safAccessLost = false);
      return;
    }
    final accessible = await PlatformBridge.isSafTreeAccessible(
      settings.downloadTreeUri,
    );
    if (mounted) setState(() => _safAccessLost = !accessible);
  }

  Future<void> _pickSafTreeAndSave() async {
    final result = await PlatformBridge.pickSafTree();
    if (result == null) return;
    final treeUri = result['tree_uri'] as String? ?? '';
    final displayName = result['display_name'] as String? ?? '';
    if (treeUri.isEmpty) return;
    final notifier = ref.read(settingsProvider.notifier);
    notifier.setStorageMode('saf');
    notifier.setDownloadTreeUri(
      treeUri,
      displayName: displayName.isNotEmpty ? displayName : treeUri,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return PopScope(
      canPop: true,
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            AppSliverHeader.page(title: context.l10n.settingsFiles),

            SliverToBoxAdapter(
              child: SettingsSectionHeader(
                title: context.l10n.setupDownloadLocationTitle,
              ),
            ),
            SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  SettingsItem(
                    icon: Icons.folder_outlined,
                    title: context.l10n.downloadDirectory,
                    subtitle: settings.downloadDirectory.isEmpty
                        ? (Platform.isIOS
                              ? context.l10n.setupAppDocumentsFolder
                              : 'Download/SpotiFLAC')
                        : settings.downloadDirectory,
                    onTap: () => _pickDirectory(context, ref),
                    showDivider: false,
                  ),
                ],
              ),
            ),
            if (Platform.isAndroid &&
                _safAccessLost &&
                settings.storageMode == 'saf' &&
                settings.downloadTreeUri.isNotEmpty)
              SliverToBoxAdapter(
                child: SettingsInfoCard(
                  icon: Icons.warning_amber_outlined,
                  tone: SettingsInfoTone.error,
                  title: context.l10n.downloadFolderAccessLostTitle,
                  message: context.l10n.downloadFolderAccessLostSubtitle,
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  action: FilledButton.tonal(
                    onPressed: () async {
                      await _pickSafTreeAndSave();
                      await _checkSafAccess();
                    },
                    child: Text(context.l10n.downloadFolderReselect),
                  ),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDirectory(BuildContext context, WidgetRef ref) async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _showIOSDirectoryOptions(context, ref);
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      _showAndroidDirectoryOptions(context, ref);
    }
  }

  Future<String> _getDefaultAndroidDirectory() async {
    const directDownloadPath = '/storage/emulated/0/Download/SpotiFLAC';
    try {
      final downloadDir = Directory(directDownloadPath);
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      return downloadDir.path;
    } catch (_) {}
    try {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final downloadDir = Directory(
          '${externalDir.parent.parent.parent.parent.path}/Download/SpotiFLAC',
        );
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        return downloadDir.path;
      }
    } catch (_) {}
    final appDir = await getApplicationDocumentsDirectory();
    final fallbackDir = Directory('${appDir.path}/SpotiFLAC');
    if (!await fallbackDir.exists()) await fallbackDir.create(recursive: true);
    return fallbackDir.path;
  }

  void _showAndroidDirectoryOptions(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final settings = ref.read(settingsProvider);
    final isSafMode =
        settings.storageMode == 'saf' && settings.downloadTreeUri.isNotEmpty;
    showAppModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                context.l10n.setupDownloadLocationTitle,
                style: Theme.of(
                  ctx,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Text(
                context.l10n.downloadLocationSubtitle,
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            AppSheetOption(
              leading: Icon(Icons.folder_special, color: colorScheme.primary),
              title: Text(context.l10n.storageAutomaticFolder),
              subtitle: Text(context.l10n.storageAutomaticDownloadFolder),
              trailing: !isSafMode ? const Icon(Icons.check) : null,
              onTap: () async {
                Navigator.pop(ctx);
                final defaultDir = await _getDefaultAndroidDirectory();
                final notifier = ref.read(settingsProvider.notifier);
                notifier.setStorageMode('app');
                notifier.setDownloadDirectory(defaultDir);
                notifier.setDownloadTreeUri('');
              },
            ),
            AppSheetOption(
              leading: Icon(Icons.folder_open, color: colorScheme.primary),
              title: Text(context.l10n.storageSafRecommended),
              subtitle: Text(context.l10n.storageDownloadFolderHint),
              trailing: isSafMode ? const Icon(Icons.check) : null,
              onTap: () async {
                Navigator.pop(ctx);
                await _pickSafTreeAndSave();
                await _checkSafAccess();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showIOSDirectoryOptions(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    showAppModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                context.l10n.setupDownloadLocationTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Text(
                context.l10n.setupDownloadLocationIosMessage,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            AppSheetOption(
              leading: Icon(Icons.folder_special, color: colorScheme.primary),
              title: Text(context.l10n.setupAppDocumentsFolder),
              subtitle: Text(context.l10n.setupAppDocumentsFolderSubtitle),
              trailing: Icon(Icons.check_circle, color: colorScheme.primary),
              onTap: () async {
                final dir = await getApplicationDocumentsDirectory();
                ref
                    .read(settingsProvider.notifier)
                    .setDownloadDirectory(dir.path);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            AppSheetOption(
              leading: Icon(
                Icons.cloud,
                color: context.isMornye
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              title: Text(context.l10n.setupChooseFromFiles),
              subtitle: Text(context.l10n.setupChooseFromFilesSubtitle),
              onTap: () async {
                Navigator.pop(ctx);
                await Future<void>.delayed(const Duration(milliseconds: 250));
                IosPickedDirectory? picked;
                try {
                  picked = await PlatformBridge.pickIosDirectory();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          context.l10n.snackbarFolderPickerFailed(
                            context.friendlyError(e),
                          ),
                        ),
                        backgroundColor: Theme.of(context).colorScheme.error,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  }
                  return;
                }
                if (picked == null || !context.mounted) return;

                final validation = validateIosPath(
                  picked.path,
                  bookmark: picked.bookmark,
                );
                if (!validation.isValid) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          validation.errorReason ??
                              context.l10n.setupIcloudNotSupported,
                        ),
                        backgroundColor: Theme.of(context).colorScheme.error,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  }
                  return;
                }

                ref
                    .read(settingsProvider.notifier)
                    .setDownloadDirectory(
                      picked.path,
                      iosBookmark: picked.bookmark,
                    );
              },
            ),
            SettingsInfoCard(
              icon: Icons.info_outline,
              tone: SettingsInfoTone.warning,
              message: context.l10n.setupIosEmptyFolderWarning,
              margin: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
