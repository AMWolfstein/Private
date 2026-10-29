import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sistrum/utils/best_effort_delete.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:sistrum/widgets/primitives/app_action_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/services/library/embedded_cover_resolver.dart';
import 'package:sistrum/utils/nav_bar_inset.dart';
import 'package:sistrum/utils/string_utils.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/status/error_card.dart';

class CacheManagementPage extends ConsumerStatefulWidget {
  const CacheManagementPage({super.key});

  @override
  ConsumerState<CacheManagementPage> createState() =>
      _CacheManagementPageState();
}

class _CacheManagementPageState extends ConsumerState<CacheManagementPage> {
  _CacheOverview? _overview;
  bool _isLoading = true;
  Object? _loadError;
  String? _busyAction;

  @override
  void initState() {
    super.initState();
    _refreshOverview();
  }

  bool get _isBusy => _busyAction != null;

  Future<void> _refreshOverview() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final overview = await _buildOverview();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.snackbarError(context.friendlyError(e))),
        ),
      );
    }
  }

  Future<_CacheOverview> _buildOverview() async {
    final appCacheDirFuture = getApplicationCacheDirectory();
    final tempDirFuture = getTemporaryDirectory();
    final appSupportDirFuture = getApplicationSupportDirectory();

    final appCacheDir = await appCacheDirFuture;
    final tempDir = await tempDirFuture;
    final appCachePath = p.normalize(appCacheDir.path);
    final tempPath = p.normalize(tempDir.path);
    final tempIsSameAsAppCache = appCachePath == tempPath;

    final appCacheStatsFuture = _scanDirectory(Directory(appCachePath));
    final tempStatsFuture = tempIsSameAsAppCache
        ? Future<_DirectoryStats?>.value(null)
        : _scanDirectory(Directory(tempPath));

    final appSupportDir = await appSupportDirFuture;
    final libraryCoverStatsFuture = _scanDirectory(
      Directory('${appSupportDir.path}/library_covers'),
    );
    final audioAnalysisStatsFuture = _scanDirectory(
      Directory('${appSupportDir.path}/audio_analysis_cache'),
    );

    final appCacheStats = await appCacheStatsFuture;
    final tempStats = await tempStatsFuture;
    final libraryCoverStats = await libraryCoverStatsFuture;
    final audioAnalysisStats = await audioAnalysisStatsFuture;

    return _CacheOverview(
      appCachePath: appCachePath,
      appCacheStats: appCacheStats,
      tempPath: tempIsSameAsAppCache ? null : tempPath,
      tempStats: tempStats,
      tempIsSameAsAppCache: tempIsSameAsAppCache,
      libraryCoverStats: libraryCoverStats,
      audioAnalysisStats: audioAnalysisStats,
    );
  }

  Future<_DirectoryStats> _scanDirectory(Directory directory) async {
    if (!await directory.exists()) {
      return const _DirectoryStats(fileCount: 0, totalSizeBytes: 0);
    }

    var fileCount = 0;
    var totalSize = 0;

    try {
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          fileCount++;
          totalSize += await entity.length();
        }
      }
    } catch (_) {}

    return _DirectoryStats(fileCount: fileCount, totalSizeBytes: totalSize);
  }

  Future<void> _clearDirectoryContents(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) return;

    try {
      final entities = <FileSystemEntity>[];
      await for (final entity in directory.list(followLinks: false)) {
        entities.add(entity);
      }

      const deleteChunkSize = 24;
      for (var i = 0; i < entities.length; i += deleteChunkSize) {
        final end = (i + deleteChunkSize < entities.length)
            ? i + deleteChunkSize
            : entities.length;
        final chunk = entities.sublist(i, end);
        await Future.wait(
          chunk.map((entity) async {
            await deleteBestEffort(entity, recursive: true);
          }),
        );
      }
    } catch (_) {}

    try {
      await directory.create(recursive: true);
    } catch (_) {}
  }

  Future<void> _clearAppCache() async {
    await EmbeddedCoverResolver.clearPersistentCache();
    final cacheDir = await getApplicationCacheDirectory();
    await _clearDirectoryContents(cacheDir.path);
  }

  Future<void> _clearTempCache() async {
    final tempDir = await getTemporaryDirectory();
    await _clearDirectoryContents(tempDir.path);
  }

  Future<void> _clearLibraryCoverCache() async {
    final appSupportDir = await getApplicationSupportDirectory();
    final libraryCoverDir = Directory('${appSupportDir.path}/library_covers');
    await _clearDirectoryContents(libraryCoverDir.path);
  }

  Future<void> _clearAudioAnalysisCache() async {
    final appSupportDir = await getApplicationSupportDirectory();
    final analysisDir = Directory('${appSupportDir.path}/audio_analysis_cache');
    await _clearDirectoryContents(analysisDir.path);
  }

  Future<void> _clearAllCaches() async {
    final currentOverview = _overview;
    await _clearAppCache();
    if (currentOverview != null && !currentOverview.tempIsSameAsAppCache) {
      await _clearTempCache();
    }
    await _clearLibraryCoverCache();
    await _clearAudioAnalysisCache();
  }

  Future<bool> _confirmClear(String target) async {
    final confirm = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(context.l10n.cacheClearConfirmTitle),
        content: Text(context.l10n.cacheClearConfirmMessage(target)),
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
            child: Text(context.l10n.dialogClear),
          ),
        ],
      ),
    );
    return confirm == true;
  }

  Future<bool> _confirmClearAll() async {
    final confirm = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(context.l10n.cacheClearAllConfirmTitle),
        content: Text(context.l10n.cacheClearAllConfirmMessage),
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
            child: Text(context.l10n.dialogClear),
          ),
        ],
      ),
    );
    return confirm == true;
  }

  Future<void> _runAction(
    String actionKey,
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    if (_isBusy || !mounted) return;
    setState(() => _busyAction = actionKey);

    try {
      await action();
      if (!mounted) return;
      if (successMessage != null && successMessage.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.snackbarError(context.friendlyError(e))),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
        await _refreshOverview();
      }
    }
  }

  Future<void> _confirmAndRunAction({
    required String actionKey,
    required String targetLabel,
    required Future<void> Function() action,
  }) async {
    final confirmed = await _confirmClear(targetLabel);
    if (!confirmed) return;

    if (!mounted) return;
    await _runAction(
      actionKey,
      action,
      successMessage: context.l10n.cacheClearSuccess(targetLabel),
    );
  }

  Future<void> _cleanupUnusedData() async {
    await _runAction('cleanup_unused', () async {
      final missingLibraryEntries = await ref
          .read(localLibraryProvider.notifier)
          .cleanupMissingFiles();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.libraryRemovedMissingFiles(missingLibraryEntries),
          ),
        ),
      );
    });
  }

  String _formatDirectorySize(_DirectoryStats stats) {
    if (stats.fileCount == 0 || stats.totalSizeBytes == 0) {
      return context.l10n.cacheNoData;
    }
    return context.l10n.cacheSizeWithFiles(
      formatBytes(stats.totalSizeBytes),
      stats.fileCount,
    );
  }

  String _buildSubtitle(String description, String sizeInfo) {
    return '$description\n$sizeInfo';
  }

  Widget _buildClearTrailing(
    String actionKey,
    String targetLabel,
    VoidCallback onPressed,
  ) {
    if (_busyAction == actionKey) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return Semantics(
      // Every row says "Clear"; name the cache it clears for TalkBack.
      label: context.l10n.cacheClearFor(targetLabel),
      button: true,
      enabled: !_isBusy,
      excludeSemantics: true,
      onTap: _isBusy ? null : onPressed,
      child: TextButton(
        onPressed: _isBusy ? null : onPressed,
        child: Text(context.l10n.dialogClear),
      ),
    );
  }

  Widget _overviewSurface({required Widget child}) {
    final scheme = Theme.of(context).colorScheme;

    final content = Padding(padding: const EdgeInsets.all(16), child: child);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(28),
        ),
        child: content,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final overview = _overview;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          AppSliverHeader.page(
            title: context.l10n.cacheTitle,
            actions: [
              IconButton(
                tooltip: context.l10n.cacheRefresh,
                onPressed: _isBusy ? null : _refreshOverview,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),

          if (!_isLoading && _loadError != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: ErrorCard(
                  error: context.friendlyError(_loadError!),
                  colorScheme: colorScheme,
                  onRetry: _refreshOverview,
                ),
              ),
            )
          else if (_isLoading || overview == null)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            SliverToBoxAdapter(
              child: _overviewSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.cacheSummaryTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.l10n.cacheEstimatedTotal(
                        formatBytes(overview.totalKnownDiskCacheBytes),
                      ),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.cacheSummarySubtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AppActionButton(
                          isDestructive: true,
                          style: FilledButton.styleFrom(
                            backgroundColor: colorScheme.secondaryContainer,
                            foregroundColor: colorScheme.onSecondaryContainer,
                          ),
                          onPressed: _isBusy
                              ? null
                              : () async {
                                  final l10n = context.l10n;
                                  final confirmed = await _confirmClearAll();
                                  if (!confirmed) return;
                                  if (!mounted) return;
                                  await _runAction(
                                    'clear_all',
                                    _clearAllCaches,
                                    successMessage: l10n.cacheClearSuccess(
                                      l10n.cacheClearAll,
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: Text(context.l10n.cacheClearAll),
                        ),
                        AppActionButton(
                          outlined: true,
                          glass: false,
                          onPressed: _isBusy ? null : _refreshOverview,
                          icon: const Icon(Icons.refresh),
                          label: Text(context.l10n.cacheRefreshStats),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: SettingsSectionHeader(
                title: context.l10n.cacheSectionStorage,
              ),
            ),
            SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  SettingsItem(
                    icon: Icons.folder_outlined,
                    title: context.l10n.cacheAppDirectory,
                    subtitle: _buildSubtitle(
                      context.l10n.cacheAppDirectoryDesc,
                      _formatDirectorySize(overview.appCacheStats),
                    ),
                    trailing: _buildClearTrailing(
                      'clear_app_cache',
                      context.l10n.cacheAppDirectory,
                      () => _confirmAndRunAction(
                        actionKey: 'clear_app_cache',
                        targetLabel: context.l10n.cacheAppDirectory,
                        action: _clearAppCache,
                      ),
                    ),
                  ),
                  if (!overview.tempIsSameAsAppCache &&
                      overview.tempStats != null)
                    SettingsItem(
                      icon: Icons.timer_outlined,
                      title: context.l10n.cacheTempDirectory,
                      subtitle: _buildSubtitle(
                        context.l10n.cacheTempDirectoryDesc,
                        _formatDirectorySize(overview.tempStats!),
                      ),
                      trailing: _buildClearTrailing(
                        'clear_temp_cache',
                        context.l10n.cacheTempDirectory,
                        () => _confirmAndRunAction(
                          actionKey: 'clear_temp_cache',
                          targetLabel: context.l10n.cacheTempDirectory,
                          action: _clearTempCache,
                        ),
                      ),
                    ),
                  SettingsItem(
                    icon: Icons.library_music_outlined,
                    title: context.l10n.cacheLibraryCover,
                    subtitle: _buildSubtitle(
                      context.l10n.cacheLibraryCoverDesc,
                      overview.libraryCoverStats.fileCount > 0 &&
                              overview.libraryCoverStats.totalSizeBytes > 0
                          ? context.l10n.cacheSizeWithFiles(
                              formatBytes(
                                overview.libraryCoverStats.totalSizeBytes,
                              ),
                              overview.libraryCoverStats.fileCount,
                            )
                          : context.l10n.cacheNoData,
                    ),
                    trailing: _buildClearTrailing(
                      'clear_library_cover_cache',
                      context.l10n.cacheLibraryCover,
                      () => _confirmAndRunAction(
                        actionKey: 'clear_library_cover_cache',
                        targetLabel: context.l10n.cacheLibraryCover,
                        action: _clearLibraryCoverCache,
                      ),
                    ),
                  ),
                  SettingsItem(
                    icon: Icons.graphic_eq_outlined,
                    title: context.l10n.cacheAudioAnalysis,
                    subtitle: _buildSubtitle(
                      context.l10n.cacheAudioAnalysisDesc,
                      overview.audioAnalysisStats.fileCount > 0 &&
                              overview.audioAnalysisStats.totalSizeBytes > 0
                          ? context.l10n.cacheSizeWithFiles(
                              formatBytes(
                                overview.audioAnalysisStats.totalSizeBytes,
                              ),
                              overview.audioAnalysisStats.fileCount,
                            )
                          : context.l10n.cacheNoData,
                    ),
                    trailing: _buildClearTrailing(
                      'clear_audio_analysis_cache',
                      context.l10n.cacheAudioAnalysis,
                      () => _confirmAndRunAction(
                        actionKey: 'clear_audio_analysis_cache',
                        targetLabel: context.l10n.cacheAudioAnalysis,
                        action: _clearAudioAnalysisCache,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SliverToBoxAdapter(
              child: SettingsSectionHeader(
                title: context.l10n.cacheSectionMaintenance,
              ),
            ),
            SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  SettingsItem(
                    icon: Icons.cleaning_services_outlined,
                    title: context.l10n.cacheCleanupUnused,
                    subtitle:
                        '${context.l10n.cacheCleanupUnusedDesc}\n${context.l10n.cacheCleanupUnusedSubtitle}',
                    trailing: _buildClearTrailing(
                      'cleanup_unused',
                      context.l10n.cacheCleanupUnused,
                      _cleanupUnusedData,
                    ),
                    showDivider: false,
                  ),
                ],
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            const NavBarSliverSpacer(),
          ],
        ],
      ),
    );
  }
}

class _CacheOverview {
  final String appCachePath;
  final _DirectoryStats appCacheStats;
  final String? tempPath;
  final _DirectoryStats? tempStats;
  final bool tempIsSameAsAppCache;
  final _DirectoryStats libraryCoverStats;
  final _DirectoryStats audioAnalysisStats;

  const _CacheOverview({
    required this.appCachePath,
    required this.appCacheStats,
    this.tempPath,
    this.tempStats,
    required this.tempIsSameAsAppCache,
    required this.libraryCoverStats,
    required this.audioAnalysisStats,
  });

  int get totalKnownDiskCacheBytes {
    return appCacheStats.totalSizeBytes +
        (tempStats?.totalSizeBytes ?? 0) +
        libraryCoverStats.totalSizeBytes +
        // The row can be cleared, so its bytes belong in the total too.
        audioAnalysisStats.totalSizeBytes;
  }
}

class _DirectoryStats {
  final int fileCount;
  final int totalSizeBytes;

  const _DirectoryStats({
    required this.fileCount,
    required this.totalSizeBytes,
  });
}
