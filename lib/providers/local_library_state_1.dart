part of 'local_library_provider.dart';

class LocalLibraryState {
  final bool isLoading;
  final bool loadFailed;
  final bool isScanning;
  final bool scanIsFinalizing;
  final bool scanIsPaused;
  final double scanProgress;
  final String? scanCurrentFile;
  final int scanTotalFiles;
  final int scannedFiles;
  final int scanErrorCount;
  final bool scanWasCancelled;
  final int totalCount;
  final int loadedIndexVersion;
  final DateTime? lastScannedAt;
  final List<LocalLibrarySource> sources;
  final String? scanningSourceId;

  /// Files the last scan of each source could not read, by source ID.
  final Map<String, LibraryScanFailures> scanFailures;
  LocalLibraryState({
    this.isLoading = false,
    this.loadFailed = false,
    this.isScanning = false,
    this.scanIsFinalizing = false,
    this.scanIsPaused = false,
    this.scanProgress = 0,
    this.scanCurrentFile,
    this.scanTotalFiles = 0,
    this.scannedFiles = 0,
    this.scanErrorCount = 0,
    this.scanWasCancelled = false,
    this.totalCount = 0,
    this.loadedIndexVersion = 0,
    this.lastScannedAt,
    this.sources = const <LocalLibrarySource>[],
    this.scanningSourceId,
    this.scanFailures = const {},
  });

  LocalLibraryState copyWith({
    bool? isLoading,
    bool? loadFailed,
    bool? isScanning,
    bool? scanIsFinalizing,
    bool? scanIsPaused,
    double? scanProgress,
    String? scanCurrentFile,
    int? scanTotalFiles,
    int? scannedFiles,
    int? scanErrorCount,
    bool? scanWasCancelled,
    int? totalCount,
    int? loadedIndexVersion,
    DateTime? lastScannedAt,
    bool clearLastScannedAt = false,
    List<LocalLibrarySource>? sources,
    String? scanningSourceId,
    bool clearScanningSourceId = false,
    Map<String, LibraryScanFailures>? scanFailures,
  }) {
    return LocalLibraryState(
      isLoading: isLoading ?? this.isLoading,
      loadFailed: loadFailed ?? this.loadFailed,
      isScanning: isScanning ?? this.isScanning,
      scanIsFinalizing: scanIsFinalizing ?? this.scanIsFinalizing,
      scanIsPaused: scanIsPaused ?? this.scanIsPaused,
      scanProgress: scanProgress ?? this.scanProgress,
      scanCurrentFile: scanCurrentFile ?? this.scanCurrentFile,
      scanTotalFiles: scanTotalFiles ?? this.scanTotalFiles,
      scannedFiles: scannedFiles ?? this.scannedFiles,
      scanErrorCount: scanErrorCount ?? this.scanErrorCount,
      scanWasCancelled: scanWasCancelled ?? this.scanWasCancelled,
      totalCount: totalCount ?? this.totalCount,
      loadedIndexVersion: loadedIndexVersion ?? this.loadedIndexVersion,
      lastScannedAt: clearLastScannedAt
          ? null
          : lastScannedAt ?? this.lastScannedAt,
      sources: sources ?? this.sources,
      scanningSourceId: clearScanningSourceId
          ? null
          : scanningSourceId ?? this.scanningSourceId,
      scanFailures: scanFailures ?? this.scanFailures,
    );
  }
}
