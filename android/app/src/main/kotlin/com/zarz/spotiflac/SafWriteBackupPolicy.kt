package com.zarz.spotiflac

/**
 * Safety rules for replacing a SAF document. SAF has no atomic replace, so the
 * previous document is copied to app cache before the destination is opened
 * with `wt`, and a successful write is verified against the staged length.
 */
internal object SafWriteBackupPolicy {
    private const val RESERVE_BYTES = 1L shl 20

    /** Whether the cache can hold the previous document plus a small margin. */
    fun canBackUp(originalBytes: Long, availableBytes: Long): Boolean =
        originalBytes >= 0 &&
            availableBytes >= originalBytes &&
            availableBytes - originalBytes >= RESERVE_BYTES

    /**
     * Providers may omit the size. A known size must match exactly; an unknown
     * size is accepted so providers that cannot report it keep working.
     */
    fun sizeMatches(expected: Long, actual: Long?): Boolean =
        actual == null || actual < 0 || actual == expected

    /** Unknown size cannot prove a rollback safe enough to discard recovery. */
    fun restoreVerified(expected: Long, restore: () -> Unit, storedSize: () -> Long?): Boolean =
        runCatching {
            restore()
            storedSize() == expected
        }.getOrDefault(false)

    fun recoveryName(now: Long, displayName: String): String {
        val safe = displayName
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .trim('.', '_')
            .takeLast(96)
            .ifBlank { "audio" }
        return "$now-$safe"
    }
}
