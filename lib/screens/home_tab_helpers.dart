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

final _recentlyAddedProvider = localHomeTracksProvider;
