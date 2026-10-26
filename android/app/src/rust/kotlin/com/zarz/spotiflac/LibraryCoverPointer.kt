package com.zarz.spotiflac

import java.io.File
import java.security.MessageDigest

/**
 * Library cover cache names.
 *
 * Covers are content addressed: tracks that embed the same artwork resolve to
 * one `cover_<sha256>.<jpg|png>` file. A `cover_<sha256 of the per-track cache
 * key>.id` pointer records which content file a track resolved to, so a later
 * scan can answer the lookup without reading the embedded artwork again.
 */
internal fun coverFileName(bytes: ByteArray, mime: String): String =
    "cover_${sha256Hex(bytes)}.${if (mime.contains("png")) "png" else "jpg"}"

internal fun coverPointerName(key: String): String =
    "cover_${sha256Hex(key.toByteArray(Charsets.UTF_8))}.id"

/** Accepts only a `cover_<64 lowercase hex>.<jpg|png>` file name. */
internal fun coverPointerTargetName(payload: String): String? =
    payload.trim().takeIf { coverFileNamePattern.matches(it) }

private val coverFileNamePattern = Regex("^cover_[0-9a-f]{64}\\.(jpg|png)$")

/** The content file a pointer names, when it is still a non-empty file. */
internal fun readCoverPointer(pointer: File, directory: File): File? {
    val payload = try {
        pointer.inputStream().use { stream ->
            val buffer = ByteArray(96)
            var length = 0
            while (length < buffer.size) {
                val count = stream.read(buffer, length, buffer.size - length)
                if (count <= 0) break
                length += count
            }
            String(buffer, 0, length, Charsets.UTF_8)
        }
    } catch (_: Exception) {
        return null
    }
    val name = coverPointerTargetName(payload) ?: return null
    return File(directory, name).takeIf { it.isFile && it.length() > 0 }
}

/** Best effort: a missing pointer only costs one artwork read on the next scan. */
internal fun writeCoverPointer(pointer: File, target: String) {
    try {
        val staged = File.createTempFile("cover_", ".tmp", pointer.parentFile)
        try {
            staged.writeText(target)
            check(staged.renameTo(pointer)) { "Could not publish library cover pointer" }
        } finally {
            staged.delete()
        }
    } catch (_: Exception) {
        // The cover itself is already cached; a pointer is only an accelerator.
    }
}

private val hexDigits = "0123456789abcdef".toCharArray()

internal fun sha256Hex(bytes: ByteArray): String {
    val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
    val text = CharArray(digest.size * 2)
    for (index in digest.indices) {
        val value = digest[index].toInt() and 0xff
        text[index * 2] = hexDigits[value ushr 4]
        text[index * 2 + 1] = hexDigits[value and 0x0f]
    }
    return String(text)
}
