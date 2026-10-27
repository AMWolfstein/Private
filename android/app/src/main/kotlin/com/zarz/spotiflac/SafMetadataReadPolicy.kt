package com.zarz.spotiflac

import java.io.File

/** How long a failed read waits before its one retry. A provider that failed
 * under load (FUSE, a busy SD card) usually answers again shortly after. */
private const val SAF_RETRY_DELAY_MS = 400L

/** The payload was read; only filename-derived metadata was available because
 * its tags are missing or unreadable. Copying the whole document to another
 * location cannot reveal different tags, so the fallback copy is skipped. */
internal class UnreadableTagsException(message: String) : Exception(message)

/** Failure belongs to this read, never to a different document or provider.
 * The direct callback owns and closes its descriptor before fallback starts. */
internal fun <T> readSafMetadataWithFallback(
    directRead: () -> T?,
    fallbackRead: () -> T?,
    accept: (T) -> Boolean = { true },
    retryDirectOnFailure: Boolean = false,
    onFailure: (Exception?) -> Unit = {},
    waitBeforeRetry: () -> Unit = { Thread.sleep(SAF_RETRY_DELAY_MS) },
): T? {
    var lastError: Exception? = null

    fun attempt(read: () -> T?): T? = try {
        read()?.takeIf(accept)
    } catch (error: Exception) {
        lastError = error
        null
    }

    fun retryDirect(): T? {
        // A remote provider may have completed its download/cache by now, and
        // a local one may have recovered from a transient error. Reopen once
        // after a short wait; never repeatedly copy whole songs or publish guesses.
        val retried = if (retryDirectOnFailure) {
            waitBeforeRetry()
            attempt(directRead)
        } else {
            null
        }
        if (retried == null) onFailure(lastError)
        return retried
    }

    val direct = attempt(directRead)
    if (direct != null) return direct
    // A descriptor read that only lacked usable tags is worth one fresh open:
    // the provider may still have been materializing the document.
    if (lastError is UnreadableTagsException) return retryDirect()
    val copied = attempt(fallbackRead)
    if (copied != null) return copied
    // The copy read the whole payload locally, so unreadable tags there are
    // final: another descriptor cannot reveal different tags. Only transport
    // failures justify reopening the document.
    if (lastError is UnreadableTagsException) {
        onFailure(lastError)
        return null
    }
    return retryDirect()
}

internal fun <T> readLyricsWithSafCopy(
    path: String,
    copyToTemp: (String) -> File?,
    read: (String) -> T,
): T? {
    if (!path.startsWith("content://")) return read(path)
    val temporary = copyToTemp(path) ?: return null
    return try {
        read(temporary.absolutePath)
    } finally {
        temporary.delete()
    }
}
