import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/screens/settings/cache/cache_management_models.dart';

DirectoryStats _stats(int bytes) =>
    DirectoryStats(fileCount: 1, totalSizeBytes: bytes);

CacheOverview _overview({DirectoryStats? temp, int analysisBytes = 0}) =>
    CacheOverview(
      appCachePath: '/cache',
      appCacheStats: _stats(100),
      tempPath: temp == null ? null : '/tmp/cache',
      tempStats: temp,
      tempIsSameAsAppCache: temp == null,
      libraryCoverStats: _stats(40),
      audioAnalysisStats: _stats(analysisBytes),
    );

void main() {
  test('the known total counts every cache area, including analysis', () {
    final overview = _overview(temp: _stats(10), analysisBytes: 5);
    expect(overview.totalKnownDiskCacheBytes, 100 + 10 + 40 + 5);
  });

  test('a missing temp directory adds nothing to the total', () {
    expect(_overview().totalKnownDiskCacheBytes, 100 + 40);
  });

  test('a directory summary keeps its file count and size', () {
    const stats = DirectoryStats(fileCount: 3, totalSizeBytes: 2048);
    expect(stats.fileCount, 3);
    expect(stats.totalSizeBytes, 2048);
  });
}
