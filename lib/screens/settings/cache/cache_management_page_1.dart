part of 'cache_management_page.dart';

extension _CacheManagementPageStatePart1 on _CacheManagementPageState {
  bool get _isBusy => _busyAction != null;
  Future<void> _refreshOverview() async {
    if (!mounted) return;
    _rebuild(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final overview = await _buildOverview();
      if (!mounted) return;
      _rebuild(() {
        _overview = overview;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      _rebuild(() {
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

  Future<CacheOverview> _buildOverview() async {
    final appCacheDirFuture = getApplicationCacheDirectory();
    final tempDirFuture = getTemporaryDirectory();
    final appSupportDirFuture = getApplicationSupportDirectory();

    final appCacheDir = await appCacheDirFuture;
    final tempDir = await tempDirFuture;
    final appCachePath = p.normalize(appCacheDir.path);
    final tempPath = p.normalize(tempDir.path);
    final tempIsSameAsAppCache = appCachePath == tempPath;

    final appCacheStatsFuture = scanCacheDirectory(Directory(appCachePath));
    final tempStatsFuture = tempIsSameAsAppCache
        ? Future<DirectoryStats?>.value(null)
        : scanCacheDirectory(Directory(tempPath));

    final appSupportDir = await appSupportDirFuture;
    final libraryCoverStatsFuture = scanCacheDirectory(
      Directory('${appSupportDir.path}/library_covers'),
    );
    final audioAnalysisStatsFuture = scanCacheDirectory(
      Directory('${appSupportDir.path}/audio_analysis_cache'),
    );

    final appCacheStats = await appCacheStatsFuture;
    final tempStats = await tempStatsFuture;
    final libraryCoverStats = await libraryCoverStatsFuture;
    final audioAnalysisStats = await audioAnalysisStatsFuture;

    return CacheOverview(
      appCachePath: appCachePath,
      appCacheStats: appCacheStats,
      tempPath: tempIsSameAsAppCache ? null : tempPath,
      tempStats: tempStats,
      tempIsSameAsAppCache: tempIsSameAsAppCache,
      libraryCoverStats: libraryCoverStats,
      audioAnalysisStats: audioAnalysisStats,
    );
  }

  Future<void> _clearAppCache() async {
    await EmbeddedCoverResolver.clearPersistentCache();
    final cacheDir = await getApplicationCacheDirectory();
    await clearCacheDirectoryContents(cacheDir.path);
  }

  Future<void> _clearTempCache() async {
    final tempDir = await getTemporaryDirectory();
    await clearCacheDirectoryContents(tempDir.path);
  }

  Future<void> _clearLibraryCoverCache() async {
    final appSupportDir = await getApplicationSupportDirectory();
    final libraryCoverDir = Directory('${appSupportDir.path}/library_covers');
    await clearCacheDirectoryContents(libraryCoverDir.path);
  }

  Future<void> _clearAudioAnalysisCache() async {
    final appSupportDir = await getApplicationSupportDirectory();
    final analysisDir = Directory('${appSupportDir.path}/audio_analysis_cache');
    await clearCacheDirectoryContents(analysisDir.path);
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
        actions: appDestructiveConfirmActions(
          context,
          cancelLabel: context.l10n.dialogCancel,
          confirmLabel: context.l10n.dialogClear,
          cancelIsDefault: true,
        ),
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
        actions: appDestructiveConfirmActions(
          context,
          cancelLabel: context.l10n.dialogCancel,
          confirmLabel: context.l10n.dialogClear,
          cancelIsDefault: true,
        ),
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
    _rebuild(() => _busyAction = actionKey);

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
        _rebuild(() => _busyAction = null);
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

  String _formatDirectorySize(DirectoryStats stats) {
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
}
