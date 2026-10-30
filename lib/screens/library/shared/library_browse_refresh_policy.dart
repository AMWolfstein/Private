import 'package:sistrum/services/library/database/library_database.dart';

bool browseLibraryCountsHaveContent(LibraryBrowseCounts counts) =>
    counts.allTrackCount > 0 ||
    counts.albumCount > 0 ||
    counts.singleTrackCount > 0;

LibraryBrowseCounts resolveLibraryBrowseCountsSnapshot({
  required LibraryBrowseCounts current,
  LibraryBrowseCounts? cached,
  LibraryBrowseCounts? nonEmptyFallback,
}) {
  if (browseLibraryCountsHaveContent(current) || nonEmptyFallback == null) {
    return current;
  }
  if (cached != null && browseLibraryCountsHaveContent(cached)) {
    return cached;
  }
  return nonEmptyFallback;
}

bool shouldRetainLibraryBrowsePageSnapshot({
  required bool currentIsEmpty,
  required bool cachedHasContent,
  required bool nonEmptyFallbackAvailable,
}) => currentIsEmpty && cachedHasContent && nonEmptyFallbackAvailable;
