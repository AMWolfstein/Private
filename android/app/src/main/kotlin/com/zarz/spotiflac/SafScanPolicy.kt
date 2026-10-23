package com.zarz.spotiflac

// Pure decisions shared by the SAF scan paths. Kept free of Android types so
// the host unit tests can cover the deletion and resume rules.

/** Returns a non-null reason when a children cursor is not authoritative. */
internal fun safListingFailureReason(loading: Boolean, error: String?): String? = when {
    loading -> "provider-loading"
    !error.isNullOrBlank() -> "provider-error: $error"
    else -> null
}

/**
 * A provider without COLUMN_LAST_MODIFIED reports 0. Zero timestamps are
 * inconclusive, so they must be rescanned rather than treated as unchanged.
 */
internal fun safFileChanged(existingModified: Long?, currentModified: Long): Boolean =
    existingModified == null ||
        existingModified == 0L ||
        currentModified == 0L ||
        existingModified != currentModified

/**
 * Base CUE document of a virtual track path, or null for a real file. Only a
 * trailing `#trackNN` marks a CUE row, so names that merely contain `#track`
 * keep their own identity.
 */
private val safCueTrackSuffix = Regex("#track\\d+$")

internal fun safCueBasePath(path: String): String? {
    val match = safCueTrackSuffix.find(path) ?: return null
    return if (match.range.first > 0) path.substring(0, match.range.first) else null
}

/**
 * A resumed full scan may still hold rows for files deleted or renamed since
 * the checkpoint. Virtual CUE rows are keyed by their backing CUE document.
 */
internal fun safScanRowIsStale(filePath: String, currentUris: Set<String>): Boolean {
    if (filePath.isBlank()) return true
    return (safCueBasePath(filePath) ?: filePath) !in currentUris
}

/** Standalone audio rows that a CUE sheet has taken over must be removed. */
internal fun safReferencedStandaloneUris(
    existingUris: Collection<String>,
    cueReferencedUris: Collection<String>,
): Set<String> = existingUris.filterTo(mutableSetOf()) { it in cueReferencedUris }

/**
 * An empty SAF listing may clear a source only when neither the current resume
 * state nor the source itself has indexed rows. Otherwise a provider that
 * answers the root probe but returns no children would wipe the library.
 */
internal fun safEmptyListingIsUntrusted(
    listedFiles: Int,
    resumeHasRows: Boolean,
    sourceHasRows: Boolean,
): Boolean = listedFiles == 0 && (resumeHasRows || sourceHasRows)

/**
 * Persist flags for a picked tree. A source that cannot persist its read grant
 * is unusable after a restart, so write-only grants fall back to read access.
 */
internal fun safTreePersistFlags(
    reportedFlags: Int,
    readFlag: Int,
    writeFlag: Int,
): List<Int> {
    val granted = reportedFlags and (readFlag or writeFlag)
    if (granted and readFlag == 0) return listOf(readFlag or writeFlag, readFlag)
    // Some providers report write access they refuse to persist; retry with
    // read-only instead of failing the picker outright.
    return listOf(granted, readFlag).distinct()
}

/** Groups existing virtual CUE rows by their backing CUE document URI. */
internal fun cueVirtualPathsByCue(existingUris: Collection<String>): Map<String, List<String>> {
    val grouped = mutableMapOf<String, MutableList<String>>()
    for (uri in existingUris) {
        val baseCueUri = safCueBasePath(uri) ?: continue
        grouped.getOrPut(baseCueUri) { mutableListOf() }.add(uri)
    }
    return grouped
}
