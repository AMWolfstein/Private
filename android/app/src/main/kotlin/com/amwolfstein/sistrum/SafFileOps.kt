package com.amwolfstein.sistrum

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile

/**
 * Generic SAF file-write utilities shared by foreground activity calls
 * (SAF io/scan, library scans, local edits). Downloads no longer use
 * this object (Phase 6 removed the download engine).
 */
object SafFileOps {
    private val safDirLock = Any()
    private const val MAX_SAF_DISPLAY_NAME_UTF8_BYTES = 180

    internal fun sanitizeFilename(name: String): String {
        var sanitized = name
            .replace("/", " ")
            .replace(Regex("[\\\\:*?\"<>|]"), " ")
            .filter { ch ->
                val code = ch.code
                !((code < 0x20 && ch != '\t' && ch != '\n' && ch != '\r') ||
                    code == 0x7F ||
                    (Character.isISOControl(ch) && ch != '\t' && ch != '\n' && ch != '\r'))
            }
            .trim()
            .trim('.', ' ')

        sanitized = sanitized
            .replace(Regex("\\s+"), " ")
            .replace(Regex("_+"), "_")
            .trim('_', ' ')

        sanitized = truncateSafDisplayName(sanitized, MAX_SAF_DISPLAY_NAME_UTF8_BYTES)
        sanitized = sanitized.trim().trim('.', ' ').trim('_', ' ')
        return if (sanitized.isBlank()) "Unknown" else sanitized
    }

    private fun truncateSafDisplayName(name: String, maxBytes: Int): String {
        if (maxBytes <= 0 || name.toByteArray(Charsets.UTF_8).size <= maxBytes) return name

        val dotIndex = name.lastIndexOf('.')
        val ext = if (
            dotIndex > 0 &&
            dotIndex < name.length - 1 &&
            name.length - dotIndex <= 10
        ) {
            name.substring(dotIndex)
        } else {
            ""
        }
        val stem = if (ext.isNotEmpty()) name.substring(0, dotIndex) else name
        val maxStemBytes = (maxBytes - ext.toByteArray(Charsets.UTF_8).size).coerceAtLeast(1)
        return truncateUtf8Bytes(stem, maxStemBytes).trim().trim('.', ' ').trim('_', ' ') + ext
    }

    private fun truncateUtf8Bytes(value: String, maxBytes: Int): String {
        if (maxBytes <= 0 || value.toByteArray(Charsets.UTF_8).size <= maxBytes) return value

        val builder = StringBuilder()
        var usedBytes = 0
        var index = 0
        while (index < value.length) {
            val codePoint = value.codePointAt(index)
            val char = String(Character.toChars(codePoint))
            val charBytes = char.toByteArray(Charsets.UTF_8).size
            if (usedBytes + charBytes > maxBytes) break
            builder.append(char)
            usedBytes += charBytes
            index += Character.charCount(codePoint)
        }
        return builder.toString()
    }

    internal fun sanitizeRelativeDir(relativeDir: String): String {
        if (relativeDir.isBlank()) return ""
        return relativeDir
            .split("/")
            .map { sanitizeFilename(it) }
            .filter { it.isNotBlank() && it != "." && it != ".." }
            .joinToString("/")
    }

    internal fun ensureDocumentDir(
        context: Context,
        treeUri: Uri,
        relativeDir: String
    ): DocumentFile? {
        val safeRelativeDir = sanitizeRelativeDir(relativeDir)
        if (safeRelativeDir.isBlank()) {
            return DocumentFile.fromTreeUri(context, treeUri)
        }

        synchronized(safDirLock) {
            var current = DocumentFile.fromTreeUri(context, treeUri) ?: return null
            val parts = safeRelativeDir.split("/").filter { it.isNotBlank() }
            for (part in parts) {
                val existing = findSafChild(context, current, part)
                current = if (existing != null && existing.isDirectory) {
                    existing
                } else {
                    val created = current.createDirectory(part) ?: return null
                    val createdName = created.name ?: part
                    if (createdName != part) {
                        created.delete()
                        findSafChild(context, current, part) ?: return null
                    } else {
                        created
                    }
                }
            }
            return current
        }
    }

    internal fun createOrReuseDocumentFile(
        context: Context,
        parent: DocumentFile,
        mimeType: String,
        fileName: String
    ): DocumentFile? {
        val safeFileName = sanitizeFilename(fileName)
        if (safeFileName.isBlank()) return null

        synchronized(safDirLock) {
            val existing = findSafChild(context, parent, safeFileName)
            if (existing != null && existing.isFile) {
                return existing
            }

            val created = parent.createFile(mimeType, safeFileName) ?: return null
            val createdName = created.name ?: safeFileName
            if (createdName == safeFileName) {
                return created
            }

            val winner = findSafChild(context, parent, safeFileName)
            if (winner != null && winner.isFile) {
                if (winner.uri != created.uri) {
                    try {
                        created.delete()
                    } catch (_: Exception) {
                    }
                }
                return winner
            }

            return created
        }
    }

}
