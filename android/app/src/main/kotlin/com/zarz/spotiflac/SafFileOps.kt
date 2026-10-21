package com.zarz.spotiflac

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream
import java.util.Locale

/**
 * Generic SAF file-write utilities shared by foreground activity calls
 * (SAF io/scan, library scans, local conversions). Downloads no longer use
 * this object (Phase 6 removed the download engine).
 */
object SafFileOps {
    private val safDirLock = Any()
    private const val MAX_SAF_DISPLAY_NAME_UTF8_BYTES = 180
    private const val STAGED_SAF_MIME_TYPE = "application/octet-stream"

    // Serializes the exists-check/create/write/publish sequence per target
    // file so concurrent writers that sanitize to the same display name
    // cannot interleave writes into one document. Different names keep
    // writing in parallel; the second same-name caller blocks, then hits
    // the exists check and reports already_exists.




    private class PublishTrace {
        private val started = System.nanoTime()
        private var previous = started
        private val stages = linkedMapOf<String, Long>()

        fun mark(stage: String) {
            val now = System.nanoTime()
            stages[stage] = (now - previous) / 1_000_000
            previous = now
        }

        fun finish(): Map<String, Long> = stages.toMap() +
            ("total" to (System.nanoTime() - started) / 1_000_000)
    }



    /**
     * Flushes and fsyncs a SAF output stream so the copied bytes are durable
     * before the staged document is renamed to its final name; without this a
     * power loss right after the rename can leave a truncated "complete" file.
     */
    fun syncOutputStream(output: OutputStream) {
        try {
            output.flush()
            (output as? FileOutputStream)?.fd?.sync()
        } catch (_: Exception) {
        }
    }

        /**
     * Swaps [document] into place under [finalName] without a window where the
     * previous file is gone but the new one is not yet in place. Any existing
     * file is renamed aside first and only deleted once the staged file holds
     * the final name; a failed swap restores it. Returns the published
     * document, or null when the swap failed (the caller owns [document]).
     */
    private fun replaceFinalDocument(
        context: Context,
        targetDir: DocumentFile,
        document: DocumentFile,
        finalName: String
    ): DocumentFile? {
        val existingFinal = findSafChild(context, targetDir, finalName)
        var aside: DocumentFile? = null
        if (existingFinal != null && existingFinal.uri != document.uri) {
            val asideName = buildReplacedSafFileName(finalName)
            try {
                findSafChild(context, targetDir, asideName)?.delete()
            } catch (_: Exception) {
            }
            if (!existingFinal.renameTo(asideName)) {
                return null
            }
            // TreeDocumentFile.renameTo updates this object's URI, including
            // providers whose document IDs change with the display name.
            aside = existingFinal
        }
        if (!document.renameTo(finalName)) {
            aside?.renameTo(finalName)
            return null
        }
        aside?.delete()
        return document
    }

    private fun buildReplacedSafFileName(fileName: String): String {
        return "${sanitizeFilename(fileName)}.replaced"
    }

















    private fun writeFileToSafLocked(
        context: Context,
        targetDir: DocumentFile,
        finalName: String,
        srcPath: String,
        trace: PublishTrace = PublishTrace(),
    ): String? {
        var stagedDocument: DocumentFile? = null
        return try {
            val ext = normalizeExt(finalName.substringAfterLast('.', ""))
            val stagedName = buildStagedSafFileName(finalName)
            deleteStaleStagedFiles(context, targetDir, finalName, ext)
            trace.mark("cleanup")
            val document = createOrReuseDocumentFile(context, targetDir, STAGED_SAF_MIME_TYPE, stagedName)
                ?: return null
            trace.mark("create")
            stagedDocument = document
            val outputStream = context.contentResolver.openOutputStream(document.uri, "wt")
            if (outputStream == null) {
                document.delete()
                stagedDocument = null
                return null
            }
            trace.mark("open")
            outputStream.use { output ->
                File(srcPath).inputStream().use { input ->
                    input.copyTo(output, bufferSize = 64 * 1024)
                }
                trace.mark("copy")
                syncOutputStream(output)
                trace.mark("sync")
            }
            trace.mark("close")

            val published = replaceFinalDocument(context, targetDir, document, finalName)
            trace.mark("replace")
            if (published == null) {
                document.delete()
                return null
            }
            stagedDocument = null
            published.uri.toString()
        } catch (e: Exception) {
            stagedDocument?.delete()
            android.util.Log.w("SpotiFLAC", "Failed to write file to SAF: ${e.message}")
            null
        }
    }



    internal fun normalizeExt(ext: String?): String {
        val trimmed = ext?.trim().orEmpty()
        if (trimmed.isEmpty()) return ""
        return if (trimmed.startsWith(".")) trimmed.lowercase(Locale.ROOT) else ".${trimmed.lowercase(Locale.ROOT)}"
    }



    private fun buildStagedSafFileName(fileName: String): String {
        val safeName = sanitizeFilename(fileName)
        return "$safeName.partial"
    }

    private fun buildLegacyStagedSafFileName(fileName: String, outputExt: String): String {
        val safeName = sanitizeFilename(fileName)
        val ext = normalizeExt(outputExt)
        if (ext.isNotBlank() && safeName.lowercase(Locale.ROOT).endsWith(ext)) {
            return safeName.dropLast(ext.length).trimEnd('.', ' ') + ".partial$ext"
        }
        val dot = safeName.lastIndexOf('.')
        if (dot > 0 && dot < safeName.lastIndex) {
            return safeName.substring(0, dot).trimEnd('.', ' ') +
                ".partial" +
                safeName.substring(dot)
        }
        return "$safeName.partial"
    }

    private fun deleteStaleStagedFiles(context: Context, parent: DocumentFile, fileName: String, outputExt: String) {
        val stagedNames = linkedSetOf(
            buildStagedSafFileName(fileName),
            buildLegacyStagedSafFileName(fileName, outputExt),
            buildReplacedSafFileName(fileName)
        )
        val staleDocuments = try {
            findSafChildren(context, parent, stagedNames)
        } catch (_: Exception) {
            return
        }
        for (document in staleDocuments.values) {
            try {
                document.delete()
            } catch (_: Exception) {
            }
        }
    }

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

    internal fun findDocumentDir(
        context: Context,
        treeUri: Uri,
        relativeDir: String
    ): DocumentFile? {
        var current = DocumentFile.fromTreeUri(context, treeUri) ?: return null
        val safeRelativeDir = sanitizeRelativeDir(relativeDir)
        if (safeRelativeDir.isBlank()) return current

        val parts = safeRelativeDir.split("/").filter { it.isNotBlank() }
        for (part in parts) {
            val existing = findSafChild(context, current, part)
            if (existing == null || !existing.isDirectory) return null
            current = existing
        }
        return current
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
