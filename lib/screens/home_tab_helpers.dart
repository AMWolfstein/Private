part of 'home_tab.dart';

class _RecentAccessView {
  final List<RecentAccessItem> uniqueItems;

  const _RecentAccessView(this.uniqueItems);
}

const _maxRecentAccessItems = 10;

final recentAccessViewProvider = Provider<_RecentAccessView>((ref) {
  final items = ref.watch(recentAccessProvider.select((s) => s.items));
  if (items.isEmpty) return const _RecentAccessView([]);

  final seen = <String>{};
  final uniqueItems = <RecentAccessItem>[];
  for (final item in items) {
    if (seen.add(item.uniqueKey)) {
      uniqueItems.add(item);
      if (uniqueItems.length >= _maxRecentAccessItems) break;
    }
  }
  return _RecentAccessView(uniqueItems);
});

const _recentlyAddedLimit = 12;

final _recentlyAddedProvider = FutureProvider<List<LocalLibraryItem>>((
  ref,
) async {
  // Re-read the library whenever a scan finishes.
  ref.watch(localLibraryProvider.select((s) => s.lastScannedAt));
  final rows = await LibraryDatabase.instance.getAll();
  final items = rows
      .map(LocalLibraryItem.fromJson)
      .where((item) => item.filePath.trim().isNotEmpty)
      .toList();
  items.sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
  return items.take(_recentlyAddedLimit).toList(growable: false);
});
