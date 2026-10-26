package com.zarz.spotiflac

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.system.Os
import android.system.OsConstants
import androidx.documentfile.provider.DocumentFile
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.time.Instant
import java.util.Locale
import java.util.UUID

// SAF/MediaStore URI IO helpers: temp copies, writes, sidecars, and the
// SAF post-processing pipeline.

internal fun errorJson(message: String): String {
        val obj = JSONObject()
        obj.put("success", false)
        obj.put("error", message)
        obj.put("message", message)
        return obj.toString()
    }

/**
 * Best-effort release of a persisted tree grant. Called when the library
 * source that used the tree is removed, so grants do not accumulate up to the
 * platform's per-app cap.
 */
internal fun MainActivity.releaseSafTreeGrant(treeUri: String) {
        if (treeUri.isBlank()) return
        val uri = try {
            Uri.parse(treeUri)
        } catch (_: Exception) {
            return
        }
        val read = Intent.FLAG_GRANT_READ_URI_PERMISSION
        val write = Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        val attempts = listOf(read or write, read, write).distinct()
        for (flags in attempts) {
            try {
                contentResolver.releasePersistableUriPermission(uri, flags)
                return
            } catch (_: Exception) {
                // Try a narrower flag set before giving up.
            }
        }
        // The tree URI is user data and the Logs screen can export it.
        android.util.Log.d("SpotiFLAC", "No persisted SAF grant to release")
    }

    /**
     * Detect whether a content URI belongs to the MediaStore provider.
     * Samsung One UI may return MediaStore URIs from SAF tree traversal,
     * which require READ_MEDIA_AUDIO / READ_EXTERNAL_STORAGE permission
     * instead of SAF tree permission.
     */
internal fun MainActivity.isMediaStoreUri(uri: Uri): Boolean {
        val authority = uri.authority ?: return false
        return authority == "media" ||
               authority.startsWith("media.") ||
               authority.contains("media")
    }

    /**
     * Resolve extension from a MediaStore URI by querying DISPLAY_NAME or MIME_TYPE.
     */
internal fun MainActivity.resolveMediaStoreExt(uri: Uri, fallbackExt: String?): String {
        try {
            contentResolver.query(uri, arrayOf(android.provider.MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val name = cursor.getString(0)?.lowercase(Locale.ROOT) ?: ""
                    val ext = extFromFileName(name)
                    if (ext.isNotBlank()) return ext
                }
            }
        } catch (_: Exception) {}

        try {
            val mime = contentResolver.getType(uri)
            val ext = extFromMimeType(mime)
            if (ext.isNotBlank()) return ext
        } catch (_: Exception) {}

        return fallbackExt ?: ""
    }

internal fun MainActivity.extFromFileName(name: String): String {
        return when {
            name.endsWith(".m4a") -> ".m4a"
            name.endsWith(".mp4") -> ".mp4"
            name.endsWith(".aac") -> ".aac"
            name.endsWith(".mp3") -> ".mp3"
            name.endsWith(".opus") -> ".opus"
            name.endsWith(".flac") -> ".flac"
            name.endsWith(".ogg") -> ".ogg"
            name.endsWith(".wave") -> ".wav"
            name.endsWith(".wav") -> ".wav"
            name.endsWith(".aiff") -> ".aiff"
            name.endsWith(".aifc") -> ".aifc"
            name.endsWith(".aif") -> ".aif"
            name.endsWith(".dsf") -> ".dsf"
            name.endsWith(".dff") -> ".dff"
            else -> ""
        }
    }

internal fun MainActivity.extFromMimeType(mime: String?): String {
        return when (mime) {
            "audio/mp4" -> ".m4a"
            "audio/aac" -> ".aac"
            "audio/eac3" -> ".m4a"
            "audio/ac3" -> ".m4a"
            "audio/ac4" -> ".m4a"
            "audio/mpeg" -> ".mp3"
            "audio/ogg" -> ".opus"
            "audio/flac" -> ".flac"
            "audio/wav", "audio/x-wav", "audio/wave", "audio/vnd.wave" -> ".wav"
            "audio/aiff", "audio/x-aiff" -> ".aiff"
            else -> ""
        }
    }

/** [displayName] skips a provider name query when the caller already listed it. */
internal fun MainActivity.copyUriToTemp(
    uri: Uri,
    fallbackExt: String? = null,
    displayName: String? = null,
): String? {
        try {
            val nameHint = (
                displayName
                    ?: try { DocumentFile.fromSingleUri(this, uri)?.name } catch (_: Exception) { null }
                    ?: uri.lastPathSegment
                    ?: ""
            ).lowercase(Locale.ROOT)
            val extFromName = extFromFileName(nameHint)
            // The MIME type only matters when the name has no extension.
            val extFromMime = if (extFromName.isNotBlank()) "" else extFromMimeType(
                try { contentResolver.getType(uri) } catch (_: Exception) { null },
            )
            val ext = if (extFromName.isNotBlank()) extFromName else if (extFromMime.isNotBlank()) extFromMime else (fallbackExt ?: "")
            val suffix = ext.ifBlank { ".tmp" }
            val tempFile = coreBackend.createTemporaryMediaFile(this, "saf_", suffix)
            return copyToTemporaryMediaFile(tempFile) {
                contentResolver.openInputStream(uri)
            }?.absolutePath
        } catch (e: SecurityException) {
            // SAF permission denied - try MediaStore fallback for Samsung One UI
            // which may return MediaStore URIs from SAF tree traversal
            if (isMediaStoreUri(uri)) {
                android.util.Log.d(
                    "SpotiFLAC",
                    "SAF denied for MediaStore URI, trying MediaStore fallback: $uri",
                )
                val result = copyMediaStoreUriToTemp(uri, fallbackExt)
                if (result != null) {
                    return result
                }
            }
            android.util.Log.w(
                "SpotiFLAC",
                "SAF read denied for $uri: ${e.message}",
            )
            return null
        } catch (e: Exception) {
            android.util.Log.w(
                "SpotiFLAC",
                "Failed copying SAF uri $uri to temp: ${e.message}",
            )
            return null
        }
    }

    /**
     * Fallback for Samsung One UI: read a MediaStore content URI using
     * READ_MEDIA_AUDIO / READ_EXTERNAL_STORAGE permission instead of SAF.
     * This handles the case where SAF tree traversal returns MediaStore URIs
     * that the SAF document provider cannot access.
     */
internal fun MainActivity.copyMediaStoreUriToTemp(uri: Uri, fallbackExt: String?): String? {
        try {
            val ext = resolveMediaStoreExt(uri, fallbackExt)
            val suffix = ext.ifBlank { ".tmp" }
            val tempFile = coreBackend.createTemporaryMediaFile(this, "ms_", suffix)
            val copied = copyToTemporaryMediaFile(tempFile) {
                contentResolver.openInputStream(uri)
            } ?: return null

            android.util.Log.d(
                "SpotiFLAC",
                "MediaStore fallback succeeded for $uri",
            )
            return copied.absolutePath
        } catch (e: Exception) {
            android.util.Log.w(
                "SpotiFLAC",
                "MediaStore fallback also failed for $uri: ${e.message}",
            )
            return null
        }
    }

internal fun MainActivity.buildUriDisplayName(
        uri: Uri,
        displayNameHint: String? = null,
        fallbackExt: String? = null,
    ): String {
        val explicitName = displayNameHint?.trim().orEmpty()
        if (explicitName.isNotEmpty()) return explicitName

        val docName = try { DocumentFile.fromSingleUri(this, uri)?.name } catch (_: Exception) { null }
        val uriName = uri.lastPathSegment
        val resolvedName = (docName ?: uriName ?: "").trim()
        if (resolvedName.isNotEmpty()) return resolvedName

        val ext = when {
            fallbackExt.isNullOrBlank().not() -> fallbackExt
            isMediaStoreUri(uri) -> resolveMediaStoreExt(uri, fallbackExt)
            else -> ""
        }
        return if (ext.isNullOrBlank()) "audio" else "audio$ext"
    }

internal fun MainActivity.buildLibraryCoverCacheKey(stablePath: String, lastModified: Long): String {
        val normalizedPath = stablePath.trim()
        if (normalizedPath.isEmpty()) return ""
        return if (lastModified > 0L) "$normalizedPath|$lastModified" else normalizedPath
    }

internal fun isSeekableSafDescriptor(descriptor: ParcelFileDescriptor): Boolean {
    return try {
        val position = Os.lseek(
            descriptor.fileDescriptor,
            0L,
            OsConstants.SEEK_CUR,
        )
        Os.lseek(descriptor.fileDescriptor, position, OsConstants.SEEK_SET)
        true
    } catch (_: Exception) {
        false
    }
}

/** Read-only metadata uses a seekable descriptor first. Capability belongs to
 * this descriptor: a pipe or revoked URI must not disable other providers. */
private fun MainActivity.readMetadataFromUri(
    uri: Uri,
    displayNameHint: String? = null,
    fallbackExt: String? = null,
    retryDirectOnFailure: Boolean = false,
    onFailure: (String) -> Unit = {},
    read: (String, String) -> JSONObject?,
): JSONObject? {
    val displayName = buildUriDisplayName(uri, displayNameHint, fallbackExt)
    return readSafMetadataWithFallback(
        directRead = {
            contentResolver.openFileDescriptor(uri, "r")?.use { descriptor ->
                if (!isSeekableSafDescriptor(descriptor)) return@use null
                read("/proc/self/fd/${descriptor.fd}", displayName)
            }
        },
        fallbackRead = {
            val tempPath = copyUriToTemp(uri, fallbackExt, displayName = displayName)
            if (tempPath == null) null else try {
                read(tempPath, displayName)
            } finally {
                try { File(tempPath).delete() } catch (_: Exception) {}
            }
        },
        retryDirectOnFailure = retryDirectOnFailure,
        onFailure = { error ->
            onFailure(error?.message ?: "No readable audio metadata for $displayName")
        },
    )
}

internal fun MainActivity.readAudioMetadataFromUri(
    uri: Uri,
    displayNameHint: String? = null,
    fallbackExt: String? = null,
    coverCacheKey: String = "",
    onFailure: (String) -> Unit = {},
): JSONObject? = readMetadataFromUri(
    uri, displayNameHint, fallbackExt,
    retryDirectOnFailure = true,
    onFailure = onFailure,
) { path, name ->
    if (name.endsWith(".dsf", true) || name.endsWith(".dff", true) || name.endsWith(".wv", true)) {
        DsdSource.open(path)?.use { source ->
            return@readMetadataFromUri JSONObject().apply {
                put("trackName", name.substringBeforeLast('.'))
                put("artistName", "Unknown Artist")
                put("albumName", "Unknown Album")
                put("filePath", uri.toString())
                // The Rust readers stamp their rows; the library import
                // requires the same scan time on this platform row.
                put("scannedAt", Instant.now().toString())
                put("format", name.substringAfterLast('.').lowercase(Locale.ROOT))
                put("sampleRate", source.rate)
                put("bitDepth", 1)
                put("duration", source.durationUs / 1000000)
                put("hasLyrics", false)
            }
        }
    }
    val obj = JSONObject(coreBackend.readAudioMetadata(
        path, name, coverCacheKey,
    ))
    if (obj.has("error")) throw IOException(obj.optString("error", "Audio metadata read failed"))
    if (obj.optBoolean("metadataFromFilename", false)) {
        // The tags are missing or unreadable, not the file: the copy fallback
        // would re-read the same bytes on every scan.
        throw UnreadableTagsException(
            obj.optString(
                "metadataReadError",
                "Audio tags unreadable; only filename-derived metadata available",
            ),
        )
    }
    obj
}

/** The Hi-Res check reads only a window from the middle of the file, so a
 * seekable descriptor avoids copying the whole track out of SAF. */


internal fun MainActivity.readCompleteMetadataFromUri(
    uri: Uri,
    displayNameHint: String? = null,
): JSONObject? = readMetadataFromUri(uri, displayNameHint) { path, name ->
    JSONObject(coreBackend.readFileMetadata(path, name)).takeUnless { it.has("error") }
}

/** Keep the resolved audio descriptor alive for quality and artwork reads.
 * Only nonseekable providers need a staged audio copy. */
internal fun MainActivity.scanCueFromUri(
    cuePath: String,
    audioUri: Uri,
    audioName: String,
    virtualPrefix: String,
    modTime: Long,
    cacheKey: String,
): String {
    val result = readMetadataFromUri(audioUri, audioName) { path, name ->
        JSONObject().put("rows", coreBackend.scanCueForLibraryWithResolvedAudio(
            cuePath, path, name, virtualPrefix, modTime, cacheKey,
        ))
    }
    return result?.getString("rows") ?: error("Could not read resolved CUE audio")
}

/** Seekable remote documents need only tag reads, not a full audio download. */
internal fun MainActivity.extractCoverFromUri(uri: Uri, outputPath: String) {
    val name = buildUriDisplayName(uri)
    contentResolver.openFileDescriptor(uri, "r")?.use { descriptor ->
        if (isSeekableSafDescriptor(descriptor)) {
            coreBackend.extractCoverToFile("/proc/self/fd/${descriptor.fd}", outputPath, name)
            return
        }
    }
    // Providers exposing a pipe cannot support random-access tag readers.
    val tempPath = copyUriToTemp(uri, displayName = name)
        ?: error("Failed to read document artwork")
    try {
        coreBackend.extractCoverToFile(tempPath, outputPath)
    } finally { File(tempPath).delete() }
}

internal data class SafWriteResult(
    val success: Boolean,
    val error: String? = null,
    val recoveryPath: String? = null,
)

internal fun MainActivity.writeUriFromPath(uri: Uri, srcPath: String): Boolean =
    writeUriFromPathRecoverable(uri, srcPath).success

/**
 * Replaces a SAF document without leaving a truncated only-copy.
 *
 * SAF providers do not offer an atomic replace, so the previous document is
 * copied to app cache first. Opening the destination with `wt` truncates it
 * immediately; if the copy or verification fails the backup is written back.
 * When even that restore fails, the backup is retained and reported so the
 * user still has a complete copy.
 */
internal fun MainActivity.writeUriFromPathRecoverable(
    uri: Uri,
    srcPath: String,
): SafWriteResult {
    val srcFile = File(srcPath)
    if (!srcFile.isFile) {
        return SafWriteResult(false, "Temporary audio file is missing")
    }
    val expected = srcFile.length()
    if (expected <= 0) {
        return SafWriteResult(false, "Temporary audio file is empty")
    }
    val displayName = runCatching { buildUriDisplayName(uri) }.getOrNull()
        ?: uri.lastPathSegment
        ?: "audio"
    val recoveryDirectory = File(cacheDir, "saf-write-recovery")
    if (!recoveryDirectory.isDirectory && !recoveryDirectory.mkdirs()) {
        return SafWriteResult(false, "Could not create a safe-write recovery directory")
    }
    // The backup must hold the previous document, which can be larger than the
    // staged replacement (for example after an artwork shrink).
    val originalBytes = runCatching {
        val stat = querySafDocumentStat(contentResolver, uri)
        if (stat.isNull("size")) null else stat.optLong("size").takeIf { it >= 0 }
    }.getOrNull()
    if (!SafWriteBackupPolicy.canBackUp(
            maxOf(expected, originalBytes ?: expected),
            recoveryDirectory.usableSpace,
        )
    ) {
        return SafWriteResult(
            false,
            "Not enough free space to update this file safely",
        )
    }
    val backup = File(
        recoveryDirectory,
        "${SafWriteBackupPolicy.recoveryName(System.currentTimeMillis(), displayName)}-" +
            UUID.randomUUID().toString().take(8),
    )
    try {
        contentResolver.openInputStream(uri)?.use { input ->
            backup.outputStream().use { output ->
                input.copyTo(output, bufferSize = 256 * 1024)
            }
        } ?: return SafWriteResult(false, "Could not read the original file")
    } catch (e: Exception) {
        backup.delete()
        return SafWriteResult(false, "Could not back up the original file: ${e.message}")
    }

    if (!SafWriteBackupPolicy.sizeMatches(backup.length(), originalBytes)) {
        backup.delete()
        return SafWriteResult(false, "Could not back up the complete original file")
    }

    return try {
        contentResolver.openOutputStream(uri, "wt")?.use { output ->
            FileInputStream(srcFile).use { input ->
                input.copyTo(output, bufferSize = 256 * 1024)
            }
        } ?: throw IOException("Could not open the document for writing")
        val actual = runCatching {
            val stat = querySafDocumentStat(contentResolver, uri)
            if (stat.isNull("size")) null else stat.optLong("size")
        }.getOrNull()
        if (!SafWriteBackupPolicy.sizeMatches(expected, actual)) {
            throw IOException("The provider stored an incomplete file")
        }
        backup.delete()
        SafWriteResult(true)
    } catch (e: Exception) {
        val restored = SafWriteBackupPolicy.restoreVerified(backup.length(), restore = {
            contentResolver.openOutputStream(uri, "wt")?.use { output ->
                backup.inputStream().use { input ->
                    input.copyTo(output, bufferSize = 256 * 1024)
                }
            } ?: throw IOException("Could not reopen the document")
        }, storedSize = {
            val stat = querySafDocumentStat(contentResolver, uri)
            if (stat.isNull("size")) null else stat.optLong("size")
        })
        if (restored) {
            backup.delete()
            SafWriteResult(false, e.message ?: "Failed to write the document")
        } else {
            SafWriteResult(
                false,
                "${e.message ?: "Failed to write the document"}; " +
                    "the original was kept at ${backup.absolutePath}",
                backup.absolutePath,
            )
        }
    }
}

    /**
     * Get the parent DocumentFile directory for a SAF document URI.
     * The child URI must be a tree-based document URI (e.g. from SAF tree scan).
     * Returns a DocumentFile that supports findFile() for sibling lookup.
     */
internal fun Context.safParentDir(childUri: Uri): DocumentFile? {
        try {
            val docId = DocumentsContract.getDocumentId(childUri)
            val treeDocId = DocumentsContract.getTreeDocumentId(childUri)
            if (docId.isNullOrEmpty() || treeDocId.isNullOrEmpty() || docId == treeDocId) return null

            // Document IDs are opaque, including when they contain slashes.
            // Ask the provider for the ancestry instead of treating IDs as paths.
            val path = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                try {
                    DocumentsContract.findDocumentPath(contentResolver, childUri)?.path
                } catch (_: Exception) {
                    null
                }
            } else null
            if (path != null) {
                if (path.size < 2 || path.first() != treeDocId || path.last() != docId) return null
                val parentUri = DocumentsContract.buildDocumentUriUsingTree(
                    childUri, path[path.lastIndex - 1]
                )
                return DocumentFile.fromTreeUri(this, parentUri)
            }

            // Older providers may only expose path-like IDs. Accept that
            // fallback only if the candidate actually lists this document.
            val lastSlash = docId.lastIndexOf('/')
            if (lastSlash <= 0) return null
            val parentUri = DocumentsContract.buildDocumentUriUsingTree(
                childUri, docId.substring(0, lastSlash)
            )
            val parent = DocumentFile.fromTreeUri(this, parentUri) ?: return null
            val name = DocumentFile.fromSingleUri(this, childUri)?.name ?: return null
            val child = findSafChild(this, parent, name) ?: return null
            return parent.takeIf { DocumentsContract.getDocumentId(child.uri) == docId }
        } catch (e: Exception) {
            android.util.Log.w("SpotiFLAC", "Failed to get SAF parent dir: ${e.message}")
            return null
        }
    }

    /**
     * Write a ".lrc" sidecar next to a SAF audio document. The sidecar reuses
     * the audio file's base name (e.g. "Song.flac" -> "Song.lrc") and is created
     * in the same parent directory. Used by re-enrich when the user's lyrics
     * mode requests an external/both sidecar. Callers must handle false so a
     * failed lyrics write cannot be reported as a successful refresh.
     */
