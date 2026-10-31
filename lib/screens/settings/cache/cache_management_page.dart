import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:sistrum/widgets/primitives/app_action_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/library/local_library_provider.dart';
import 'package:sistrum/services/library/covers/embedded_cover_resolver.dart';
import 'package:sistrum/screens/settings/cache/cache_management_models.dart';
import 'package:sistrum/screens/settings/cache/cache_directory_tools.dart';
import 'package:sistrum/utils/layout/nav_bar_inset.dart';
import 'package:sistrum/utils/text/string_utils.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/status/error_card.dart';

part 'cache_management_actions.dart';

class CacheManagementPage extends ConsumerStatefulWidget {
  const CacheManagementPage({super.key});

  @override
  ConsumerState<CacheManagementPage> createState() =>
      _CacheManagementPageState();
}

class _CacheManagementPageState extends ConsumerState<CacheManagementPage> {
  CacheOverview? _overview;
  bool _isLoading = true;
  Object? _loadError;
  String? _busyAction;

  @override
  void initState() {
    super.initState();
    _refreshOverview();
  }

  void _rebuild(VoidCallback fn) => setState(fn);

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
