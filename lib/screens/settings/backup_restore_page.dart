import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:spotiflac_android/widgets/app_alert_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/user_profile_provider.dart';
import 'package:spotiflac_android/services/backup_service.dart';
import 'package:spotiflac_android/services/history_database.dart';
import 'package:spotiflac_android/utils/logger.dart';
import 'package:spotiflac_android/utils/nav_bar_inset.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';

class BackupRestorePage extends ConsumerStatefulWidget {
  const BackupRestorePage({super.key});

  @override
  ConsumerState<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends ConsumerState<BackupRestorePage> {
  static final _log = AppLogger('BackupRestorePage');

  bool _isExporting = false;
  bool _isImporting = false;
  // Held from the picker until the restore (or its cancellation) finishes, so
  // a second Import tap cannot start a competing restore.
  bool _restoring = false;
  bool _includeSettings = true;
  bool _includeHistory = true;
  bool _includeCollections = true;

  bool get _isBusy => _isExporting || _isImporting || _restoring;
  bool get _hasSelection =>
      _includeSettings || _includeHistory || _includeCollections;

  Future<void> _createBackup() async {
    if (_isBusy || !_hasSelection) return;
    setState(() => _isExporting = true);
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final settings = _includeSettings
          ? ref.read(settingsProvider).toJson()
          : null;
      String? collectionsJson;
      var covers = <String, Map<String, String>>{};
      if (_includeCollections) {
        final notifier = ref.read(libraryCollectionsProvider.notifier);
        collectionsJson = await notifier.exportCollectionsJson();
        covers = await notifier.exportPlaylistCoverFiles();
      }
      final file = await BackupService.writeBackupArchive(
        settings: settings,
        profile: _includeSettings
            ? await ref.read(userProfileProvider.future)
            : null,
        includeHistory: _includeHistory,
        loadHistoryPage: (limit, offset) =>
            HistoryDatabase.instance.getAll(limit: limit, offset: offset),
        collections: const {},
        collectionsJson: collectionsJson,
        playlistCoverFiles: covers,
        extensions: const {},
      );

      messenger.showSnackBar(SnackBar(content: Text(l10n.backupCreated)));

      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: l10n.backupTitle),
      );
    } catch (e, stack) {
      _log.e('Failed to create backup: $e', e, stack);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is BackupTooLargeException
                ? l10n.backupTooLarge
                : l10n.backupCreateFailed,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _restoreBackup() async {
    if (_isBusy) return;
    setState(() => _restoring = true);
    try {
      await _runRestore();
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _runRestore() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);

    BackupBundle? bundle;
    try {
      // Android resolves custom extensions to MIME types. It recognizes JSON
      // but not SFLB, so mixing them hides our own backups. Validate contents
      // with BackupService after selection instead of filtering by extension.
      final picked = await FilePicker.pickFile(type: FileType.any);
      if (picked == null) return;
      final path = picked.path;
      bundle = path != null
          ? await BackupService.parseFile(path)
          : BackupService.parse(utf8.decode(await picked.readAsBytes()));
    } catch (e) {
      _log.e('Failed to read backup file: $e');
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupInvalidFile)));
      return;
    }

    if (bundle == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupInvalidFile)));
      return;
    }

    if (!mounted) {
      await bundle.cleanup();
      return;
    }
    final confirmed = await _confirmRestore(bundle);
    if (confirmed != true || !mounted) {
      await bundle.cleanup();
      return;
    }

    setState(() => _isImporting = true);
    final applied = <String>[];
    try {
      if (bundle.profile != null) {
        await ref
            .read(userProfileProvider.notifier)
            .restoreFromBackup(bundle.profile!);
        applied.add(l10n.profileTitle);
      }
      if (bundle.hasSettings) {
        await ref
            .read(settingsProvider.notifier)
            .restoreFromBackup(bundle.settings!);
        applied.add(l10n.backupContentsSettings);
      }
      if (bundle.hasHistory) {
        await BackupService.restoreHistory(bundle);
        applied.add(l10n.backupContentsHistory(bundle.historyCount));
      }
      if (bundle.hasCollections) {
        await ref
            .read(libraryCollectionsProvider.notifier)
            .restoreFromBackup(
              bundle.collections,
              coverImages: bundle.playlistCovers,
            );
        applied.add(l10n.backupSelectCollections);
      }

      final message = StringBuffer(l10n.backupRestored)
        ..write('\n')
        ..write(l10n.backupRestoreRestartHint);

      messenger.showSnackBar(
        SnackBar(
          content: Text(message.toString()),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e, stack) {
      _log.e('Failed to restore backup: $e', e, stack);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            applied.isEmpty
                ? l10n.backupRestoreFailed
                : l10n.backupRestorePartiallyFailed(applied.join(', ')),
          ),
        ),
      );
    } finally {
      await bundle.cleanup();
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<bool?> _confirmRestore(BackupBundle bundle) {
    final l10n = context.l10n;
    return showAppDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AppAlertDialog(
          title: Text(l10n.backupRestoreConfirmTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.backupSelectedRestoreMessage),
              const SizedBox(height: 8),
              Text(l10n.backupListeningStatisticsExcluded),
              const SizedBox(height: 16),
              Text(
                l10n.backupContentsTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              if (bundle.hasSettings)
                _ContentRow(
                  icon: Icons.settings_outlined,
                  label: l10n.backupContentsSettings,
                ),
              if (bundle.profile != null)
                _ContentRow(
                  icon: Icons.person_outline,
                  label: l10n.profileTitle,
                ),
              if (bundle.hasHistory)
                _ContentRow(
                  icon: Icons.history,
                  label: l10n.backupContentsHistory(bundle.historyCount),
                ),
              if (bundle.hasCollections)
                _ContentRow(
                  icon: Icons.favorite_outline,
                  label: l10n.backupContentsLiked(bundle.likedCount),
                ),
              if (bundle.hasCollections)
                _ContentRow(
                  icon: Icons.queue_music_outlined,
                  label: l10n.backupContentsPlaylists(bundle.playlistCount),
                ),
              if (bundle.favoriteArtistCount > 0)
                _ContentRow(
                  icon: Icons.person_outline,
                  label: l10n.backupContentsArtists(bundle.favoriteArtistCount),
                ),
            ],
          ),
          actions: [
            AppDialogAction(
              isDefault: true,
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.dialogCancel),
            ),
            AppDialogAction(
              filled: true,
              isDestructive: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.backupRestoreConfirmButton),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          AppSliverHeader.page(title: l10n.backupTitle),
          SliverToBoxAdapter(
            child: SettingsSectionHeader(title: l10n.backupExportSectionTitle),
          ),
          SliverToBoxAdapter(
            child: SettingsGroup(
              children: [
                SettingsItem(
                  icon: Icons.settings_outlined,
                  title: l10n.backupSettingsOnly,
                  onTap: _isBusy
                      ? null
                      : () => setState(() {
                          _includeSettings = true;
                          _includeHistory = false;
                          _includeCollections = false;
                        }),
                ),
                SettingsSwitchItem(
                  icon: Icons.settings_outlined,
                  title: l10n.backupContentsSettings,
                  subtitle: l10n.backupIncludesProfile,
                  value: _includeSettings,
                  onChanged: _isBusy
                      ? null
                      : (value) => setState(() => _includeSettings = value),
                ),
                SettingsSwitchItem(
                  icon: Icons.history,
                  title: l10n.backupSelectHistory,
                  subtitle: l10n.backupListeningStatisticsExcluded,
                  value: _includeHistory,
                  onChanged: _isBusy
                      ? null
                      : (value) => setState(() => _includeHistory = value),
                ),
                SettingsSwitchItem(
                  icon: Icons.library_music_outlined,
                  title: l10n.backupSelectCollections,
                  subtitle: l10n.backupSelectCollectionsDescription,
                  value: _includeCollections,
                  onChanged: _isBusy
                      ? null
                      : (value) => setState(() => _includeCollections = value),
                ),
                SettingsItem(
                  icon: Icons.ios_share,
                  title: l10n.backupExportButton,
                  subtitle: _hasSelection
                      ? l10n.backupSelectedExportDescription
                      : l10n.backupSelectAtLeastOne,
                  onTap: _isBusy || !_hasSelection ? null : _createBackup,
                  trailing: _isExporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  showDivider: false,
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsSectionHeader(title: l10n.backupImportSectionTitle),
          ),
          SliverToBoxAdapter(
            child: SettingsGroup(
              children: [
                SettingsItem(
                  icon: Icons.settings_backup_restore,
                  title: l10n.backupImportButton,
                  subtitle: l10n.backupImportSectionDescription,
                  onTap: _isBusy ? null : _restoreBackup,
                  trailing: _isImporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  showDivider: false,
                ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          const NavBarSliverSpacer(),
        ],
      ),
    );
  }
}

class _ContentRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ContentRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
