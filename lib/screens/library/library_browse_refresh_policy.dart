import 'package:sistrum/services/library/library_database.dart';

bool browseLibraryCountsHaveContent(LibraryBrowseCounts counts) =>
    counts.allTrackCount > 0 ||
    counts.albumCount > 0 ||
    counts.singleTrackCount > 0;

LibraryBrowseCounts resolveLibraryBrowseCountsSnapshot({
  required LibraryBrowseCounts current,
  LibraryBrowseCounts? cached,
  LibraryBrowseCounts? activeDownloadFallback,
}) {
  if (browseLibraryCountsHaveContent(current) ||
      activeDownloadFallback == null) {
    return current;
  }
  if (cached != null && browseLibraryCountsHaveContent(cached)) {
    return cached;
  }
  return activeDownloadFallback;
}

bool shouldRetainLibraryBrowsePageSnapshot({
  required bool currentIsEmpty,
  required bool cachedHasContent,
  required bool activeDownloadFallbackAvailable,
}) => currentIsEmpty && cachedHasContent && activeDownloadFallbackAvailable;
