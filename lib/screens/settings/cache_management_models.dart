class CacheOverview {
  final String appCachePath;
  final DirectoryStats appCacheStats;
  final String? tempPath;
  final DirectoryStats? tempStats;
  final bool tempIsSameAsAppCache;
  final DirectoryStats libraryCoverStats;
  final DirectoryStats audioAnalysisStats;

  const CacheOverview({
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

class DirectoryStats {
  final int fileCount;
  final int totalSizeBytes;

  const DirectoryStats({required this.fileCount, required this.totalSizeBytes});
}
