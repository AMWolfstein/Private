import 'package:flutter_test/flutter_test.dart';

import 'package:sistrum/screens/library/library_browse_refresh_policy.dart';
import 'package:sistrum/services/library/library_database.dart';

void main() {
  const empty = LibraryBrowseCounts(
    allTrackCount: 0,
    albumCount: 0,
    singleTrackCount: 0,
  );
  const cached = LibraryBrowseCounts(
    allTrackCount: 20,
    albumCount: 2,
    singleTrackCount: 3,
  );
  const fallback = LibraryBrowseCounts(
    allTrackCount: 15,
    albumCount: 1,
    singleTrackCount: 4,
  );

  test('keeps cached counts when a refresh returns empty', () {
    final resolved = resolveLibraryBrowseCountsSnapshot(
      current: empty,
      cached: cached,
      nonEmptyFallback: fallback,
    );

    expect(identical(resolved, cached), isTrue);
  });

  test('uses the in-memory snapshot when no page cache exists yet', () {
    final resolved = resolveLibraryBrowseCountsSnapshot(
      current: empty,
      nonEmptyFallback: fallback,
    );

    expect(identical(resolved, fallback), isTrue);
  });

  test('allows a legitimate empty refresh without a snapshot fallback', () {
    final resolved = resolveLibraryBrowseCountsSnapshot(
      current: empty,
      cached: cached,
    );

    expect(identical(resolved, empty), isTrue);
    expect(
      shouldRetainLibraryBrowsePageSnapshot(
        currentIsEmpty: true,
        cachedHasContent: true,
        nonEmptyFallbackAvailable: false,
      ),
      isFalse,
    );
  });

  test('retains a non-empty page only while its fallback is available', () {
    expect(
      shouldRetainLibraryBrowsePageSnapshot(
        currentIsEmpty: true,
        cachedHasContent: true,
        nonEmptyFallbackAvailable: true,
      ),
      isTrue,
    );
    expect(
      shouldRetainLibraryBrowsePageSnapshot(
        currentIsEmpty: false,
        cachedHasContent: true,
        nonEmptyFallbackAvailable: true,
      ),
      isFalse,
    );
  });
}
