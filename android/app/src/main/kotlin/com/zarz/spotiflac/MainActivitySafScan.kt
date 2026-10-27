package com.zarz.spotiflac

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document.MIME_TYPE_DIR
import androidx.documentfile.provider.DocumentFile
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

// SAF library-scan subsystem: tree walking, incremental diff, CUE resolution,
// and scan-progress state shared with the progress stream in MainActivity.

internal fun MainActivity.buildStableLibraryId(filePath: String): String {
        val digest = MessageDigest.getInstance("SHA-1")
        val bytes = digest.digest(filePath.toByteArray(Charsets.UTF_8))
        val hex = bytes.joinToString("") { "%02x".format(it) }
        return "lib_$hex"
    }

internal fun resetSafScanProgress() {
    synchronized(MainActivity.safScanLock) {
        MainActivity.safScanProgress = MainActivity.SafScanProgress()
    }
}

internal fun updateSafScanProgress(block: (MainActivity.SafScanProgress) -> Unit) {
    synchronized(MainActivity.safScanLock) {
        block(MainActivity.safScanProgress)
    }
}

/** How many failed documents a finished scan lists with their reason. The
 * error count still includes the rest. */
internal const val REPORTED_SCAN_FAILURES = 100

internal fun recordSafScanFailure(path: String, message: String) {
    updateSafScanProgress {
        if (it.failures.size < REPORTED_SCAN_FAILURES) {
            it.failures = it.failures + (path to message)
        }
    }
}

internal fun safProgressToJson(): String {
    val snapshot = synchronized(MainActivity.safScanLock) {
        MainActivity.safScanProgress.copy()
    }
    val obj = JSONObject()
    obj.put("total_files", snapshot.totalFiles)
    obj.put("scanned_files", snapshot.scannedFiles)
    obj.put("current_file", snapshot.currentFile)
    obj.put("error_count", snapshot.errorCount)
    obj.put("progress_pct", snapshot.progressPct)
    obj.put("is_complete", snapshot.isComplete)
    // Sent once complete, as the Rust scanner does, so updates stay small.
    if (snapshot.isComplete && snapshot.failures.isNotEmpty()) {
        obj.put("failures", JSONArray(snapshot.failures.map { (path, message) ->
            JSONObject().put("path", path).put("message", message)
        }))
    }
    return obj.toString()
}

internal fun readLibraryScanProgressJson(coreBackend: CoreBackend): String {
    return if (MainActivity.safScanActive) {
        safProgressToJson()
    } else {
        coreBackend.getLibraryScanProgress()
    }
}


internal fun MainActivity.loadExistingFilesFromSnapshot(snapshotPath: String): MutableMap<String, Long> {
        val result = mutableMapOf<String, Long>()
        if (snapshotPath.isBlank()) {
            return result
        }

        val snapshotFile = File(snapshotPath)
        if (!snapshotFile.exists()) {
            return result
        }

        snapshotFile.forEachLine { line ->
            if (line.isBlank()) return@forEachLine
            val separatorIndex = line.indexOf('\t')
            if (separatorIndex <= 0 || separatorIndex >= line.length - 1) {
                return@forEachLine
            }
            val modTime = line.substring(0, separatorIndex).toLongOrNull() ?: 0L
            val filePath = line.substring(separatorIndex + 1)
            if (filePath.isNotEmpty()) {
                result[filePath] = modTime
            }
        }
        return result
    }



private data class SafFileInspectionRequest(
    val key: String,
    val treeUri: String,
    val relativeDir: String,
    val currentUri: String,
    val fileNames: List<String>,
)

/**
 * Inspects many SAF history entries while walking each document tree at most
 * once. The old per-file resolver could repeat a 20k-document breadth-first
 * search for every missing history row and every conversion filename variant.
 */


private fun safScanCheckpointPath(outputPath: String): String = "$outputPath.state"

private fun loadSafScanCheckpoint(path: String): MutableMap<String, Long> {
    val checkpoint = File(path)
    if (!checkpoint.exists()) return mutableMapOf()
    val entries = mutableMapOf<String, Long>()
    try {
        checkpoint.forEachLine(Charsets.UTF_8) { line ->
            val separator = line.indexOf('\t')
            if (separator <= 0) return@forEachLine
            val uri = line.substring(0, separator)
            val modified = line.substring(separator + 1).toLongOrNull() ?: return@forEachLine
            entries[uri] = modified
        }
    } catch (e: Exception) {
        android.util.Log.w("SpotiFLAC", "SAF scan: failed reading checkpoint: ${e.message}")
    }
    return entries
}

private fun reconcileSafScanCheckpoint(
    outputPath: String,
    loaded: MutableMap<String, Long>,
): MutableMap<String, Long> {
    val output = File(outputPath)
    if (!output.exists()) return loaded

    val outputEntries = mutableMapOf<String, Long>()
    try {
        output.forEachLine(Charsets.UTF_8) { line ->
            if (line.isBlank()) return@forEachLine
            try {
                val obj = JSONObject(line)
                val filePath = obj.optString("filePath", "").trim()
                if (filePath.isNotBlank()) {
                    val modified = obj.optLong("fileModTime", 0L)
                    val key = safCueBasePath(filePath) ?: filePath
                    outputEntries[key] = modified
                }
            } catch (_: Exception) {}
        }
    } catch (e: Exception) {
        android.util.Log.w("SpotiFLAC", "SAF scan: failed reconciling checkpoint: ${e.message}")
        return loaded
    }

    loaded.clear()
    loaded.putAll(outputEntries)
    return loaded
}

private fun countSafScanRows(path: String): Int {
    val output = File(path)
    if (!output.exists()) return 0
    return try {
        output.useLines(Charsets.UTF_8) { lines -> lines.count { it.isNotBlank() } }
    } catch (e: Exception) {
        android.util.Log.w("SpotiFLAC", "SAF scan: failed counting existing rows: ${e.message}")
        0
    }
}

// One read per block while repairing an interrupted scan output.
private const val safScanRepairBlockBytes = 8 * 1024

/**
 * Truncates an interrupted NDJSON scan output to its last complete line.
 * The search walks backwards in blocks: an interrupted row is one line that can
 * be megabytes of JSON, so a byte-at-a-time read costs thousands of syscalls.
 * Kept internal so the host tests can cover the boundary cases.
 */
internal fun repairSafScanOutput(path: String) {
    val output = File(path)
    if (!output.exists()) return
    try {
        RandomAccessFile(output, "rw").use { file ->
            var end = file.length()
            val block = ByteArray(safScanRepairBlockBytes)
            while (end > 0) {
                val size = minOf(block.size.toLong(), end).toInt()
                val start = end - size
                file.seek(start)
                file.readFully(block, 0, size)
                for (offset in size - 1 downTo 0) {
                    if (block[offset] == '\n'.code.toByte()) {
                        file.setLength(start + offset + 1)
                        return
                    }
                }
                end = start
            }
            // No complete line survived the interruption.
            file.setLength(0)
        }
    } catch (e: Exception) {
        android.util.Log.w("SpotiFLAC", "SAF scan: failed repairing output: ${e.message}")
    }
}

/**
 * Drops resumed rows whose file (or backing CUE document) is no longer in the
 * current traversal. Without this, a scan interrupted before a deletion is
 * resumed would import the deleted file's row from the surviving NDJSON output.
 */
private fun pruneSafScanResume(outputPath: String, currentUris: Set<String>) {
    val output = File(outputPath)
    if (!output.exists()) return
    try {
        val survivors = mutableListOf<String>()
        var droppedOutput = false
        output.forEachLine(Charsets.UTF_8) { line ->
            if (line.isBlank()) return@forEachLine
            val filePath = try {
                JSONObject(line).optString("filePath", "")
            } catch (_: Exception) {
                droppedOutput = true
                return@forEachLine
            }
            if (safScanRowIsStale(filePath, currentUris)) {
                droppedOutput = true
            } else {
                survivors.add(line)
            }
        }
        if (droppedOutput) {
            output.bufferedWriter(Charsets.UTF_8).use { writer ->
                for (line in survivors) {
                    writer.write(line)
                    writer.newLine()
                }
            }
        }

        val checkpoint = File(safScanCheckpointPath(outputPath))
        if (!checkpoint.exists()) return
        val kept = mutableListOf<String>()
        var droppedCheckpoint = false
        checkpoint.forEachLine(Charsets.UTF_8) { line ->
            val separator = line.indexOf('\t')
            if (separator <= 0) {
                droppedCheckpoint = true
                return@forEachLine
            }
            val uri = line.substring(0, separator)
            if (safScanRowIsStale(uri, currentUris)) {
                droppedCheckpoint = true
            } else {
                kept.add(line)
            }
        }
        if (droppedCheckpoint) {
            checkpoint.bufferedWriter(Charsets.UTF_8).use { writer ->
                for (line in kept) {
                    writer.write(line)
                    writer.newLine()
                }
            }
        }
    } catch (e: Exception) {
        android.util.Log.w("SpotiFLAC", "SAF scan: failed pruning resumed output: ${e.message}")
    }
}


    /**
     * Extract the audio filename referenced by a CUE sheet file.
     * Reads the FILE "name" TYPE line from the .cue text.
     * Returns just the filename (no path), or null if not found.
     */
internal fun MainActivity.extractCueAudioFileName(cueTempPath: String): String? {
        try {
            return File(cueTempPath).useLines { cueAudioFileName(it.asIterable()) }
        } catch (e: Exception) {
            android.util.Log.w("SpotiFLAC", "Failed to extract audio filename from CUE: ${e.message}")
        }
        return null
    }

    /**
     * Read the FILE line straight from the SAF descriptor. An unchanged sheet
     * only needs its backing audio resolved; copying the sheet to a temporary
     * file first buys nothing.
     */
internal fun MainActivity.readCueAudioFileNameFromUri(uri: Uri): String? {
    return try {
        contentResolver.openInputStream(uri)?.bufferedReader(Charsets.UTF_8)?.useLines { lines ->
            // Stop at FILE without a temporary copy or a fixed prefix limit:
            // valid sheets may put a long REM preamble before the filename.
            cueAudioFileName(lines.asIterable())
        }
    } catch (e: Exception) {
        android.util.Log.w(
            "SpotiFLAC",
            "SAF scan: failed reading CUE header: ${e.javaClass.simpleName}",
        )
        null
    }
}

    private val cueSiblingAudioExtensions = listOf(
        ".flac", ".wav", ".ape", ".mp3", ".ogg", ".wv", ".m4a", ".mp4", ".aac"
    )

    // Keep the SAF folder walk aligned with the backend's supported audio formats.
    // CUE files are handled separately.
    private val libraryScanAudioExtensions = setOf(
        ".flac", ".m4a", ".mp4", ".aac", ".mp3", ".opus", ".ogg",
        ".ape", ".wv", ".mpc", ".wav", ".aiff", ".aif", ".dsf", ".dff"
    )

internal fun MainActivity.getSafChildFileLookup(
        dir: DocumentFile,
        cache: MutableMap<String, Map<String, SafChildEntry>>,
    ): Map<String, SafChildEntry> {
        val dirKey = dir.uri.toString()
        return cache.getOrPut(dirKey) { safChildFileLookup(listSafChildrenOrThrow(dir)) }
    }

private fun safChildFileLookup(children: List<SafChildEntry>): Map<String, SafChildEntry> =
    buildMap {
        for (child in children) {
            if (child.isDirectory) continue
            val childName = child.name?.trim().orEmpty()
            if (childName.isBlank()) continue
            put(childName.lowercase(Locale.ROOT), child)
        }
    }

/** Keeps a traversal listing for CUE sibling lookup so the directory is not
 * queried again; on network providers every listing is a round trip. */
private fun rememberCueDirectoryListing(
    dir: DocumentFile,
    children: List<SafChildEntry>,
    cache: MutableMap<String, Map<String, SafChildEntry>>,
) {
    if (children.any { !it.isDirectory && it.name?.endsWith(".cue", ignoreCase = true) == true }) {
        cache[dir.uri.toString()] = safChildFileLookup(children)
    }
}

// Provider round trips dominate on SD cards, USB drives and network shares.
private const val SAF_LIST_CONCURRENCY = 4
private const val SAF_READ_WORKERS = 6
private const val SAF_SCAN_PAUSE_POLL_MS = 100L

/**
 * Holds a SAF scan at its checkpoint while paused, keeping its position in
 * memory. Returns true when the scan should stop because it was cancelled.
 */
internal fun safScanStopRequested(cancelled: () -> Boolean = { false }): Boolean {
    while (MainActivity.safScanPaused && !MainActivity.safScanCancel && !cancelled()) {
        Thread.sleep(SAF_SCAN_PAUSE_POLL_MS)
    }
    return MainActivity.safScanCancel || cancelled()
}

/**
 * Prefetches the listings of directories already waiting in a breadth-first
 * queue. The caller still dequeues, deduplicates and records errors serially,
 * so traversal order and results match a one-directory-at-a-time walk.
 * Idle daemon threads exit on their own, so abandoned walks leak nothing.
 */
private class SafTreeLister(private val context: Context) {
    private val executor = ThreadPoolExecutor(
        SAF_LIST_CONCURRENCY,
        SAF_LIST_CONCURRENCY,
        1,
        TimeUnit.SECONDS,
        LinkedBlockingQueue(),
    ) { runnable -> Thread(runnable, "saf-scan-list").apply { isDaemon = true } }
        .apply { allowCoreThreadTimeOut(true) }
    private val prefetched = mutableMapOf<String, Future<Result<List<SafChildEntry>>>>()

    private fun submit(dir: DocumentFile) = executor.submit<Result<List<SafChildEntry>>> {
        try {
            Result.success(context.listSafChildrenOrThrow(dir))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    fun list(
        dir: DocumentFile,
        queue: Collection<Pair<DocumentFile, String>>,
        visited: Set<String>,
    ): Result<List<SafChildEntry>> {
        val uri = dir.uri.toString()
        val current = prefetched.remove(uri) ?: submit(dir)
        for ((next, _) in queue) {
            if (prefetched.size >= SAF_LIST_CONCURRENCY * 2) break
            val nextUri = next.uri.toString()
            if (nextUri == uri || nextUri in visited || nextUri in prefetched) continue
            prefetched[nextUri] = submit(next)
        }
        return try {
            current.get()
        } catch (e: ExecutionException) {
            throw e.cause ?: e
        }
    }
}

/**
 * Runs [task] on a bounded pool and passes each result to [consume] in input
 * order. A sliding window keeps workers busy past one slow file. Returns
 * false when cancelled.
 */
private fun <T, R> runSafReadsInOrder(
    items: List<T>,
    cancelled: () -> Boolean,
    task: (T) -> R,
    consume: (T, Result<R>) -> Unit,
): Boolean {
    if (items.isEmpty()) return true
    val workers = minOf(SAF_READ_WORKERS, items.size)
    val executor = Executors.newFixedThreadPool(workers)
    try {
        val window = workers * 4
        val inFlight = ArrayDeque<Pair<T, Future<R>>>(window)
        var next = 0
        while (next < items.size || inFlight.isNotEmpty()) {
            if (cancelled()) {
                inFlight.forEach { it.second.cancel(true) }
                return false
            }
            while (inFlight.size < window && next < items.size) {
                val item = items[next++]
                inFlight.addLast(item to executor.submit<R> { task(item) })
            }
            val (item, future) = inFlight.removeFirst()
            val result = try {
                Result.success(future.get())
            } catch (e: ExecutionException) {
                Result.failure(e.cause ?: e)
            } catch (e: Exception) {
                Result.failure(e)
            }
            consume(item, result)
        }
        return true
    } finally {
        executor.shutdownNow()
    }
}

/** Resolves the backing audio from the traversal listing, keeping the name and
 * timestamp the listing already returned instead of querying the document. */
internal fun MainActivity.resolveCueAudioEntry(
        parentDir: DocumentFile,
        cueName: String,
        audioFileName: String?,
        childLookupCache: MutableMap<String, Map<String, SafChildEntry>>,
    ): SafChildEntry? {
        val childLookup = getSafChildFileLookup(parentDir, childLookupCache)

        val directMatch = audioFileName
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?.substringAfterLast("/")
            ?.substringAfterLast("\\")
            ?.lowercase(Locale.ROOT)
            ?.let(childLookup::get)
        if (directMatch != null) {
            return directMatch
        }

        val cueBaseName = cueName.substringBeforeLast('.').trim()
        if (cueBaseName.isBlank()) {
            return null
        }

        val cueBaseKey = cueBaseName.lowercase(Locale.ROOT)
        for (ext in cueSiblingAudioExtensions) {
            childLookup["$cueBaseKey$ext"]?.let { return it }
        }
        return null
    }

internal data class SafChildEntry(
    val doc: DocumentFile,
    val name: String?,
    val isDirectory: Boolean,
    val lastModified: Long,
    val isFile: Boolean,
)

internal fun Context.listSafChildrenOrThrow(
    dir: DocumentFile,
    includeLastModified: Boolean = true,
): List<SafChildEntry> {
    for (attempt in 0..2) {
        try {
            return querySafChildrenOrThrow(dir, includeLastModified)
        } catch (error: SafProviderLoadingException) {
            if (attempt == 2) throw error
            Thread.sleep(300L * (attempt + 1))
        }
    }
    throw IOException("SAF directory listing did not complete")
}

private class SafProviderLoadingException(uri: Uri) :
    IOException("SAF provider is still loading $uri; retry the scan when it is ready")

private fun Context.querySafChildrenOrThrow(
    dir: DocumentFile,
    includeLastModified: Boolean,
): List<SafChildEntry> {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            dir.uri,
            DocumentsContract.getDocumentId(dir.uri),
        )
        val projection = mutableListOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        if (includeLastModified) projection.add(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
        val cursor = try {
            contentResolver.query(childrenUri, projection.toTypedArray(), null, null, null)
        } catch (_: Exception) {
            // A few older providers reject the richer projection; retry with IDs.
            contentResolver.query(
                childrenUri,
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID),
                null,
                null,
                null,
            )
        } ?: throw IOException("SAF provider returned no cursor for ${dir.uri}")
        return cursor.use {
            // Network DocumentsProviders may return cached/partial rows, or an
            // empty cursor with EXTRA_ERROR, while fetching a directory. Never
            // commit either as an empty/full scan.
            val loading = it.extras.getBoolean(DocumentsContract.EXTRA_LOADING, false)
            val providerError = it.extras.getString(DocumentsContract.EXTRA_ERROR)
            when (safListingFailureReason(loading, providerError)) {
                null -> Unit
                "provider-loading" -> throw SafProviderLoadingException(dir.uri)
                else -> throw IOException(
                    "SAF provider error for ${dir.uri}: $providerError",
                )
            }
            val documentIdIndex = it.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            )
            val displayNameIndex = it.getColumnIndex(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            )
            val mimeTypeIndex = it.getColumnIndex(
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            )
            val lastModifiedIndex = it.getColumnIndex(
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            )
            buildList {
                while (it.moveToNext()) {
                    val childUri = DocumentsContract.buildDocumentUriUsingTree(
                        dir.uri,
                        it.getString(documentIdIndex),
                    )
                    val child = DocumentFile.fromTreeUri(this@querySafChildrenOrThrow, childUri)
                        ?: throw IOException("Invalid SAF child URI: $childUri")
                    val name = if (displayNameIndex >= 0 && !it.isNull(displayNameIndex)) {
                        it.getString(displayNameIndex)
                    } else {
                        try { child.name } catch (_: Exception) { null }
                    }
                    val mimeType = if (mimeTypeIndex >= 0 && !it.isNull(mimeTypeIndex)) {
                        it.getString(mimeTypeIndex)
                    } else {
                        null
                    }
                    val isDirectory = if (mimeType != null) {
                        mimeType == MIME_TYPE_DIR
                    } else {
                        try { child.isDirectory } catch (_: Exception) { false }
                    }
                    val isFile = if (mimeType != null) {
                        mimeType.isNotEmpty() && !isDirectory
                    } else {
                        !isDirectory && try { child.isFile } catch (_: Exception) { false }
                    }
                    val lastModified = if (!includeLastModified) {
                        0L
                    } else if (
                        lastModifiedIndex >= 0 && !it.isNull(lastModifiedIndex)
                    ) {
                        it.getLong(lastModifiedIndex)
                    } else {
                        try { child.lastModified() } catch (_: Exception) { 0L }
                    }
                    add(SafChildEntry(child, name, isDirectory, lastModified, isFile))
                }
            }
        }
    }

internal fun Context.resolveReadableSafTreeOrThrow(
        treeUriStr: String,
    ): Triple<Uri, DocumentFile, List<SafChildEntry>> {
        if (treeUriStr.isBlank()) {
            throw IllegalArgumentException("SAF tree URI is empty")
        }
        val treeUri = Uri.parse(treeUriStr)
        val root = DocumentFile.fromTreeUri(this, treeUri)
            ?: throw IOException("Unable to resolve SAF tree")
        val hasReadPermission = contentResolver.persistedUriPermissions.any {
            it.uri == treeUri && it.isReadPermission
        } || checkUriPermission(
            root.uri,
            android.os.Process.myPid(),
            android.os.Process.myUid(),
            Intent.FLAG_GRANT_READ_URI_PERMISSION,
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasReadPermission) {
            throw SecurityException("Read access to the SAF tree has been revoked")
        }
        // canRead() also requires a non-empty MIME type from queryDocument.
        // Remote providers can omit that metadata after reconnecting even
        // though queryChildDocuments can read the folder. The real listing is
        // authoritative; reuse it in the scan instead of another round trip.
        for (attempt in 0..2) {
            val children = listSafChildrenOrThrow(root)
            if (children.isNotEmpty() || root.exists()) {
                return Triple(treeUri, root, children)
            }
            // An empty listing without a confirmed root is inconclusive,
            // never evidence that previously indexed songs were deleted.
            if (attempt < 2) Thread.sleep(300L * (attempt + 1))
        }
        throw IOException("SAF provider could not confirm the library folder; reconnect it and retry")
    }

internal fun MainActivity.scanSafTree(
        treeUriStr: String,
        ndjsonOutputPath: String? = null,
        sourceHasRows: Boolean = false,
    ): Any {
        fun cancelledResult(): Any {
            updateSafScanProgress { it.isComplete = true }
            if (ndjsonOutputPath == null) return "[]"
            // Preserve partial output so the next scan can resume.
            throw java.util.concurrent.CancellationException("SAF library scan cancelled")
        }

        val (_, root, rootChildren) = resolveReadableSafTreeOrThrow(treeUriStr)

        resetSafScanProgress()
        MainActivity.safScanCancel = false
        MainActivity.safScanActive = true
        updateSafScanProgress {
            it.currentFile = "Scanning folders..."
        }

        val supportedAudioExt = libraryScanAudioExtensions
        data class SafAudioEntry(
            val doc: DocumentFile,
            val name: String,
            val lastModified: Long,
        )
        data class SafCueEntry(
            val doc: DocumentFile,
            val parentDir: DocumentFile,
            val name: String,
            val lastModified: Long,
        )
        val audioFiles = mutableListOf<SafAudioEntry>()
        val cueFiles = mutableListOf<SafCueEntry>()
        // Every file seen by this traversal; used to prune a resumed output.
        val listedUris = mutableSetOf<String>()
        val visitedDirUris = mutableSetOf<String>()
        val safChildLookupCache = mutableMapOf<String, Map<String, SafChildEntry>>()
        var traversalErrors = 0

        val queue: ArrayDeque<Pair<DocumentFile, String>> = ArrayDeque()
        queue.add(root to "")
        val lister = SafTreeLister(this)

        while (queue.isNotEmpty()) {
            if (safScanStopRequested()) {
                return cancelledResult()
            }

            val (dir, path) = queue.removeFirst()
            val dirUri = dir.uri.toString()
            if (!visitedDirUris.add(dirUri)) {
                continue
            }

            val listing = if (dir.uri == root.uri) {
                Result.success(rootChildren)
            } else {
                lister.list(dir, queue, visitedDirUris)
            }
            val children = listing.getOrNull()
            if (children == null) {
                traversalErrors++
                updateSafScanProgress { it.errorCount = traversalErrors }
                reportLibraryScanError(dirUri, "List folder", listing.exceptionOrNull()?.message ?: "No directory listing")
                continue
            }
            rememberCueDirectoryListing(dir, children, safChildLookupCache)

            for (child in children) {
                if (safScanStopRequested()) {
                    return cancelledResult()
                }

                try {
                    if (child.isDirectory) {
                        val childName = child.name ?: continue
                        val childPath = if (path.isBlank()) childName else "$path/$childName"
                        val childUri = child.doc.uri.toString()
                        if (childUri == dirUri || visitedDirUris.contains(childUri)) {
                            continue
                        }
                        queue.add(child.doc to childPath)
                    } else {
                        // Keep the row even when the name is unavailable: a
                        // resumed scan must not treat incomplete metadata as
                        // deletion.
                        listedUris.add(child.doc.uri.toString())
                        val name = child.name ?: continue
                        val lastModified = child.lastModified
                        val ext = name.substringAfterLast('.', "").lowercase(Locale.ROOT)
                        if (ext == "cue") {
                            cueFiles.add(SafCueEntry(child.doc, dir, name, lastModified))
                        } else if (ext.isNotBlank() && supportedAudioExt.contains(".$ext")) {
                            audioFiles.add(SafAudioEntry(child.doc, name, lastModified))
                        }
                    }
                } catch (e: Exception) {
                    traversalErrors++
                    updateSafScanProgress { it.errorCount = traversalErrors }
                    reportLibraryScanError(child.doc.uri.toString(), "Inspect entry", e.message ?: e.javaClass.simpleName)
                }
            }
        }

        if (traversalErrors > 0) {
            throw IOException("SAF traversal failed for $traversalErrors entries")
        }

        // Resume state survives an interrupted scan, but a completed or forced
        // scan deletes it, so the caller also reports whether the source holds
        // rows. Either one makes an empty listing untrustworthy.
        val hadIndexedRows = ndjsonOutputPath?.let {
            val output = File(it)
            val checkpoint = File(safScanCheckpointPath(it))
            (output.exists() && output.length() > 0L) ||
                (checkpoint.exists() && checkpoint.length() > 0L)
        } == true

        // A resumed output may still hold rows for files deleted or renamed
        // since the checkpoint was written. The listing just completed is
        // authoritative, so drop those rows before importing them again. An
        // empty listing is not authoritative, so it must not prune the state
        // that resume depends on.
        if (ndjsonOutputPath != null && listedUris.isNotEmpty()) {
            pruneSafScanResume(ndjsonOutputPath, listedUris)
        }
        val earlyCheckpoint = ndjsonOutputPath
            ?.takeIf {
                File(it).exists() && File(safScanCheckpointPath(it)).exists()
            }
            ?.let { loadSafScanCheckpoint(safScanCheckpointPath(it)) }
            ?: mutableMapOf()

        fun emptyResult(): Any {
            if (ndjsonOutputPath == null) return "[]"
            // A listing with no files at all is never evidence that every
            // indexed file was deleted: a provider can fail silently and still
            // answer the root probe. Rows are cleared by the explicit
            // missing-file cleanup instead.
            if (safEmptyListingIsUntrusted(listedUris.size, hadIndexedRows, sourceHasRows)) {
                throw IOException("SAF scan listed no files; reconnect the folder and retry")
            }
            File(ndjsonOutputPath).writeText("", Charsets.UTF_8)
            try { File(safScanCheckpointPath(ndjsonOutputPath)).delete() } catch (_: Exception) {}
            return mapOf("path" to ndjsonOutputPath, "count" to 0, "error_count" to 0)
        }

        val totalItems = audioFiles.size + cueFiles.size
        updateSafScanProgress {
            it.totalFiles = totalItems
            if (earlyCheckpoint.isEmpty()) {
                it.currentFile = "Scanning folders..."
            } else {
                it.currentFile = "Resuming scan..."
                if (totalItems > 0) {
                    it.scannedFiles = earlyCheckpoint.size.coerceAtMost(totalItems)
                    it.progressPct = it.scannedFiles.toDouble() / totalItems.toDouble() * 100.0
                }
            }
        }

        if (audioFiles.isEmpty() && cueFiles.isEmpty()) {
            updateSafScanProgress {
                it.isComplete = true
                it.progressPct = 100.0
            }
            return emptyResult()
        }

        // Stream results to a spill file: a full-library scan's JSONArray plus
        // its serialized string would otherwise hold the whole payload on the
        // Java heap several times over.
        val spill = if (ndjsonOutputPath == null) this.SpillJsonWriter() else null
        val outputPath = ndjsonOutputPath
        val checkpointPath = outputPath?.let(::safScanCheckpointPath)
        val checkpoint = if (checkpointPath != null) {
            val outputFile = File(requireNotNull(outputPath))
            val checkpointFile = File(checkpointPath)
            outputFile.parentFile?.mkdirs()
            // Discard stale output that has no checkpoint.
            if (outputFile.exists() && !checkpointFile.exists()) {
                try { outputFile.delete() } catch (_: Exception) {}
            } else if (!outputFile.exists() && checkpointFile.exists()) {
                try { checkpointFile.delete() } catch (_: Exception) {}
            }
            repairSafScanOutput(outputFile.absolutePath)
            reconcileSafScanCheckpoint(
                outputFile.absolutePath,
                loadSafScanCheckpoint(checkpointPath),
            )
        } else {
            mutableMapOf()
        }
        val checkpointWriter = checkpointPath?.let {
            FileOutputStream(File(it), true).bufferedWriter(Charsets.UTF_8)
        }
        val ndjsonWriter = outputPath?.let {
            FileOutputStream(File(it), true).bufferedWriter(Charsets.UTF_8)
        }
        var resultCount = outputPath?.let(::countSafScanRows) ?: 0
        // A checkpoint entry means the row was already appended. Comparing
        // timestamps here would rescan everything on providers that report 0
        // and append a duplicate row for each file, so presence is the resume
        // contract; the next incremental scan still picks up real changes.
        fun checkpointed(uri: String): Boolean = checkpoint.containsKey(uri)

        fun recordCheckpoint(uri: String, lastModified: Long) {
            if (checkpointWriter == null || uri.isBlank()) return
            checkpoint[uri] = lastModified
            checkpointWriter.write(uri)
            checkpointWriter.write('\t'.code)
            checkpointWriter.write(lastModified.toString())
            checkpointWriter.newLine()
            checkpointWriter.flush()
        }

        fun putResult(obj: JSONObject) {
            if (ndjsonWriter != null) {
                ndjsonWriter.write(obj.toString())
                ndjsonWriter.newLine()
            } else {
                spill!!.raw(if (resultCount == 0) "[" else ",")
                spill.raw(obj.toString())
            }
            resultCount++
        }
        try {
        var scanned = checkpoint.size.coerceAtMost(totalItems)
        var errors = traversalErrors

        fun reportProgress() {
            val pct = if (totalItems > 0) {
                scanned.toDouble() / totalItems.toDouble() * 100.0
            } else {
                100.0
            }
            updateSafScanProgress {
                it.scannedFiles = scanned
                it.errorCount = errors
                it.progressPct = pct
            }
        }

        val cueReferencedAudioUris = mutableSetOf<String>()

        for (cue in cueFiles) {
            val cueDoc = cue.doc
            val parentDir = cue.parentDir
            val cueUri = cueDoc.uri.toString()
            val cueAlreadyIndexed = checkpointed(cueUri)
            if (safScanStopRequested()) {
                ndjsonWriter?.close()
                spill?.abandon()
                return cancelledResult()
            }

            val cueName = cue.name
            updateSafScanProgress { it.currentFile = cueName }

            var tempCuePath: String? = null
            try {
                tempCuePath = copyUriToTemp(cueDoc.uri, ".cue", cueName)
                if (tempCuePath == null) {
                    errors++
                    reportLibraryScanError(cueUri, "Read CUE", "Failed to copy CUE file")
                    if (!cueAlreadyIndexed) {
                        scanned++
                        reportProgress()
                    }
                    continue
                }

                val audioFileName = extractCueAudioFileName(tempCuePath)

                val audioEntry = resolveCueAudioEntry(
                    parentDir = parentDir,
                    cueName = cueName,
                    audioFileName = audioFileName,
                    childLookupCache = safChildLookupCache,
                )

                if (audioEntry == null) {
                    reportLibraryScanError(cueUri, "Resolve CUE audio", "No audio file found for $cueName")
                    errors++
                    if (!cueAlreadyIndexed) {
                        scanned++
                        reportProgress()
                    }
                    continue
                }

                if (cueAlreadyIndexed) {
                    // The earlier pass already produced this sheet's rows, so it
                    // still owns the backing audio.
                    cueReferencedAudioUris.add(audioEntry.doc.uri.toString())
                    // This entry is already part of `scanned` (checkpoint size);
                    // counting it again would double the percentage.
                    continue
                }

                val audioName = audioEntry.name?.takeIf { it.isNotBlank() } ?: "audio.flac"
                val audioLastModified = audioEntry.lastModified
                val coverCacheKey = buildLibraryCoverCacheKey(
                    audioEntry.doc.uri.toString(),
                    audioLastModified,
                )

                val cueLastModified = cue.lastModified

                val cueResultsJson = scanCueFromUri(
                    tempCuePath,
                    audioEntry.doc.uri,
                    audioName,
                    cueDoc.uri.toString(),
                    cueLastModified,
                    coverCacheKey,
                )

                val cueArray = JSONArray(cueResultsJson)
                for (j in 0 until cueArray.length()) {
                    putResult(cueArray.getJSONObject(j))
                }
                if (safCueProducedRows(cueArray.length())) {
                    cueReferencedAudioUris.add(audioEntry.doc.uri.toString())
                }
                ndjsonWriter?.flush()
                recordCheckpoint(cueUri, cue.lastModified)

            } catch (e: Exception) {
                errors++
                reportLibraryScanError(cueUri, "Scan CUE", e.message ?: e.javaClass.simpleName)
            } finally {
                try { tempCuePath?.let { File(it).delete() } } catch (_: Exception) {}
            }

            if (!cueAlreadyIndexed) {
                scanned++
                reportProgress()
            }
        }

        data class SafAudioScanOutcome(
            val uri: String,
            val name: String,
            val lastModified: Long,
            val metadata: JSONObject?,
            val error: String?,
        )

        val pendingAudio = mutableListOf<SafAudioEntry>()
        // Skip resumable and CUE entries before parallel reads.
        for (audio in audioFiles) {
            val doc = audio.doc
            if (safScanStopRequested()) {
                ndjsonWriter?.close()
                spill?.abandon()
                return cancelledResult()
            }

            val stableUri = doc.uri.toString()
            val lastModified = audio.lastModified
            if (checkpointed(stableUri)) {
                continue
            }
            if (cueReferencedAudioUris.contains(stableUri)) {
                recordCheckpoint(stableUri, lastModified)
                scanned++
                reportProgress()
                continue
            }
            pendingAudio.add(audio)
        }

        // Descriptor reads stream from the provider without copying, so the
        // pool is bounded by provider round trips rather than copy memory.
        val completed = runSafReadsInOrder(
            pendingAudio,
            cancelled = { safScanStopRequested() },
            task = { audio ->
                val doc = audio.doc
                val stableUri = doc.uri.toString()
                val name = audio.name
                val lastModified = audio.lastModified
                val ext = name.substringAfterLast('.', "").lowercase(Locale.ROOT)
                val fallbackExt = if (ext.isNotBlank()) ".${ext}" else null
                val coverCacheKey = buildLibraryCoverCacheKey(stableUri, lastModified)
                var error: String? = null
                val metadata = try {
                    readAudioMetadataFromUri(
                        doc.uri,
                        name,
                        fallbackExt,
                        coverCacheKey,
                        onFailure = { error = it },
                    )
                } catch (e: Exception) {
                    error = e.message ?: e.javaClass.simpleName
                    null
                }
                SafAudioScanOutcome(stableUri, name, lastModified, metadata, error)
            },
        ) { audio, result ->
            val outcome = result.getOrNull()
            if (outcome == null) {
                errors++
                val error = result.exceptionOrNull()
                reportLibraryScanError(audio.doc.uri.toString(), "Read metadata", error?.message ?: "Metadata task failed")
            } else {
                updateSafScanProgress { it.currentFile = outcome.name }
                val metadataObj = outcome.metadata
                if (metadataObj == null) {
                    errors++
                    reportLibraryScanError(outcome.uri, "Read metadata", outcome.error ?: "No readable audio metadata for ${outcome.name}")
                } else {
                    try {
                        metadataObj.put("id", buildStableLibraryId(outcome.uri))
                        metadataObj.put("filePath", outcome.uri)
                        metadataObj.put("fileModTime", outcome.lastModified)
                        putResult(metadataObj)
                        // Flush before recording the checkpoint to avoid losing the row.
                        ndjsonWriter?.flush()
                        recordCheckpoint(outcome.uri, outcome.lastModified)
                    } catch (error: Exception) {
                        errors++
                        reportLibraryScanError(outcome.uri, "Index track", error.message ?: error.javaClass.simpleName)
                    }
                }
            }

            scanned++
            reportProgress()
        }
        if (!completed) {
            ndjsonWriter?.close()
            spill?.abandon()
            return cancelledResult()
        }

        updateSafScanProgress {
            it.isComplete = true
            it.progressPct = 100.0
        }

        if (ndjsonWriter != null) {
            ndjsonWriter.close()
            checkpointWriter?.close()
            return mapOf("path" to outputPath, "count" to resultCount, "error_count" to errors)
        }
        spill!!.raw(if (resultCount == 0) "[]" else "]")
        return spill.result()
        } catch (e: Exception) {
            try { ndjsonWriter?.close() } catch (_: Exception) {}
            try { checkpointWriter?.close() } catch (_: Exception) {}
            spill?.abandon()
            // Preserve partial output for resume.
            throw e
        }
    }

    /**
     * Incremental SAF tree scan - only scans new or modified files.
     * Supports .cue sheets: expands them into virtual track entries and
     * deduplicates audio files referenced by CUE sheets.
     * @param treeUriStr The SAF tree URI to scan
     * @param existingFilesJson JSON object mapping file URI -> lastModified timestamp
     * @return JSON object with new/changed files and removed URIs
     */
internal fun MainActivity.scanSafTreeIncremental(treeUriStr: String, existingFilesJson: String): Any {
        val existingFiles = mutableMapOf<String, Long>()
        try {
            val obj = JSONObject(existingFilesJson)
            val keys = obj.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                existingFiles[key] = obj.optLong(key, 0)
            }
        } catch (_: Exception) {}
        return scanSafTreeIncremental(treeUriStr, existingFiles)
    }

internal fun MainActivity.scanSafTreeIncremental(
        treeUriStr: String,
        existingFiles: Map<String, Long>,
        cancelled: () -> Boolean = { false },
    ): Any {
        val (_, root, rootChildren) = resolveReadableSafTreeOrThrow(treeUriStr)

        resetSafScanProgress()
        MainActivity.safScanCancel = false
        MainActivity.safScanActive = true
        updateSafScanProgress {
            it.currentFile = "Scanning folders..."
        }

        val supportedAudioExt = libraryScanAudioExtensions
        // Names and timestamps come from the directory listing; querying each
        // document again costs a provider round trip per changed file.
        data class ChangedAudio(
            val doc: DocumentFile,
            val name: String,
            val lastModified: Long,
            val parentDir: DocumentFile,
        )
        data class CueEntry(
            val doc: DocumentFile,
            val parentDir: DocumentFile,
            val name: String,
            val lastModified: Long,
        )
        val audioFiles = mutableListOf<ChangedAudio>()
        val cueFilesToScan = mutableListOf<CueEntry>()
        val unchangedCueFiles = mutableListOf<CueEntry>()
        val currentUris = mutableSetOf<String>()
        val visitedDirUris = mutableSetOf<String>()
        val safChildLookupCache = mutableMapOf<String, Map<String, SafChildEntry>>()
        var traversalErrors = 0

        val existingCueVirtualPaths = cueVirtualPathsByCue(existingFiles.keys)

        val queue: ArrayDeque<Pair<DocumentFile, String>> = ArrayDeque()
        queue.add(root to "")
        val lister = SafTreeLister(this)

        while (queue.isNotEmpty()) {
            if (safScanStopRequested(cancelled)) {
                updateSafScanProgress { it.isComplete = true }
                val result = JSONObject()
                result.put("files", JSONArray())
                result.put("removedUris", JSONArray())
                result.put("skippedCount", 0)
                result.put("totalFiles", 0)
                result.put("error_count", traversalErrors)
                result.put("cancelled", true)
                return result.toString()
            }

            val (dir, path) = queue.removeFirst()
            val dirUri = dir.uri.toString()
            if (!visitedDirUris.add(dirUri)) {
                continue
            }

            val listing = if (dir.uri == root.uri) {
                Result.success(rootChildren)
            } else {
                lister.list(dir, queue, visitedDirUris)
            }
            val children = listing.getOrNull()
            if (children == null) {
                traversalErrors++
                updateSafScanProgress { it.errorCount = traversalErrors }
                reportLibraryScanError(dirUri, "List folder", listing.exceptionOrNull()?.message ?: "No directory listing")
                continue
            }
            rememberCueDirectoryListing(dir, children, safChildLookupCache)

            for (child in children) {
                if (safScanStopRequested(cancelled)) {
                    updateSafScanProgress { it.isComplete = true }
                    val result = JSONObject()
                    result.put("files", JSONArray())
                    result.put("removedUris", JSONArray())
                    result.put("skippedCount", 0)
                    result.put("totalFiles", 0)
                    result.put("error_count", traversalErrors)
                    result.put("cancelled", true)
                    return result.toString()
                }

                try {
                    if (child.isDirectory) {
                        val childName = child.name ?: continue
                        val childPath = if (path.isBlank()) childName else "$path/$childName"
                        val childUri = child.doc.uri.toString()
                        if (childUri == dirUri || visitedDirUris.contains(childUri)) {
                            continue
                        }
                        queue.add(child.doc to childPath)
                    } else {
                        val uriStr = child.doc.uri.toString()
                        currentUris.add(uriStr)

                        val name = child.name ?: continue
                        val ext = name.substringAfterLast('.', "").lowercase(Locale.ROOT)

                        if (ext == "cue") {
                            val lastModified = child.lastModified

                            val virtualPaths =
                                existingCueVirtualPaths[uriStr].orEmpty()
                            val existingModified = virtualPaths.firstOrNull()?.let { existingFiles[it] }

                            if (!safFileChanged(existingModified, lastModified)) {
                                unchangedCueFiles.add(CueEntry(child.doc, dir, name, lastModified))
                                currentUris.addAll(virtualPaths)
                            } else {
                                cueFilesToScan.add(CueEntry(child.doc, dir, name, lastModified))
                            }
                        } else if (ext.isNotBlank() && supportedAudioExt.contains(".$ext")) {
                            val existingModified = existingFiles[uriStr]
                            val lastModified = child.lastModified

                            if (safFileChanged(existingModified, lastModified)) {
                                audioFiles.add(ChangedAudio(child.doc, name, lastModified, dir))
                            }
                        }
                    }
                } catch (e: Exception) {
                    traversalErrors++
                    updateSafScanProgress { it.errorCount = traversalErrors }
                    reportLibraryScanError(child.doc.uri.toString(), "Inspect entry", e.message ?: e.javaClass.simpleName)
                }
            }
        }

        if (traversalErrors > 0) {
            throw IOException("SAF traversal failed for $traversalErrors entries")
        }

        // A provider that answers the root probe but lists no files must not be
        // read as "every file was deleted": that would wipe the source's rows.
        if (currentUris.isEmpty() && existingFiles.isNotEmpty()) {
            throw IOException("SAF scan found no files while the library index is not empty")
        }

        var errors = traversalErrors
        val cueReferencedAudioUris = mutableSetOf<String>()
        // CUE sheets whose backing audio could not be resolved. Only the named
        // audio of a sheet with retained rows is skipped; unrelated songs in
        // the same folder must still be indexed.
        val unresolvedCueAudioKeys = mutableSetOf<String>()
        val cuesToRescan = mutableListOf<CueEntry>()

        fun unresolvedCueAudioKey(dir: DocumentFile, name: String): String =
            dir.uri.toString() + "\u0000" + name.lowercase(Locale.ROOT)

        // Unchanged CUEs are not re-parsed, but their audio still has to be
        // claimed so the standalone audio row is not indexed twice. A changed
        // audio file also invalidates the CUE's cached timestamps.
        for (cue in unchangedCueFiles) {
            if (safScanStopRequested(cancelled)) {
                updateSafScanProgress { it.isComplete = true }
                val result = JSONObject()
                result.put("files", JSONArray())
                result.put("removedUris", JSONArray())
                result.put("skippedCount", 0)
                result.put("totalFiles", 0)
                result.put("error_count", errors)
                result.put("cancelled", true)
                return result.toString()
            }
            var audioFileName: String? = null
            try {
                // The sheet is unchanged: read its FILE line from the document
                // itself instead of copying it to a temporary file.
                audioFileName = readCueAudioFileNameFromUri(cue.doc.uri)
                // The CUE/audio basename fallback works without the header, so
                // a read failure does not orphan the backing audio.
                val audioEntry = resolveCueAudioEntry(
                    parentDir = cue.parentDir,
                    cueName = cue.name,
                    audioFileName = audioFileName,
                    childLookupCache = safChildLookupCache,
                )
                if (audioEntry == null) {
                    errors++
                    // Report the display name: the Logs screen can export paths.
                    reportLibraryScanError(cue.name, "Resolve CUE audio", "No audio file found for ${cue.name}")
                    // This sheet's rows are still indexed; keep its named audio
                    // from being added as a duplicate standalone row.
                    audioFileName?.let {
                        unresolvedCueAudioKeys.add(unresolvedCueAudioKey(cue.parentDir, it))
                    }
                    continue
                }
                val audioUri = audioEntry.doc.uri.toString()
                cueReferencedAudioUris.add(audioUri)
                if (safFileChanged(existingFiles[audioUri], audioEntry.lastModified)) {
                    cuesToRescan.add(cue)
                }
            } catch (e: Exception) {
                errors++
                // Keep provider text (which can embed the folder URI) out of the
                // shareable log; CONC-104 tracks the remaining call sites.
                reportLibraryScanError(cue.name, "Resolve CUE audio", e.javaClass.simpleName)
                audioFileName?.let {
                    unresolvedCueAudioKeys.add(unresolvedCueAudioKey(cue.parentDir, it))
                }
            }
        }
        cueFilesToScan.addAll(cuesToRescan)

        fun removalUris(): List<String> = (
            existingFiles.keys.filter { it !in currentUris } +
                safReferencedStandaloneUris(existingFiles.keys, cueReferencedAudioUris)
            ).distinct()

        val totalFiles = currentUris.size
        val filesToProcess = audioFiles.size + cueFilesToScan.size
        val skippedCount = (totalFiles - filesToProcess).coerceAtLeast(0)
        val hasPendingAudio = audioFiles.any { audio ->
            audio.doc.uri.toString() !in cueReferencedAudioUris &&
                unresolvedCueAudioKey(audio.parentDir, audio.name) !in unresolvedCueAudioKeys
        }

        updateSafScanProgress {
            it.totalFiles = totalFiles
        }

        if (!hasPendingAudio && cueFilesToScan.isEmpty()) {
            updateSafScanProgress {
                it.isComplete = true
                it.scannedFiles = totalFiles
                it.errorCount = errors
                it.progressPct = 100.0
            }
            val result = JSONObject()
            result.put("files", JSONArray())
            result.put("removedUris", JSONArray(removalUris()))
            result.put("skippedCount", skippedCount)
            result.put("totalFiles", totalFiles)
            result.put("error_count", errors)
            return result.toString()
        }

        // Stream changed-file entries to a spill file — after a cache loss an
        // incremental scan can be as large as a full scan.
        val spill = this.SpillJsonWriter()
        spill.raw("{\"files\":[")
        var fileCount = 0
        fun putFile(obj: JSONObject) {
            if (fileCount > 0) spill.raw(",")
            spill.raw(obj.toString())
            fileCount++
        }
        var scanned = 0

        fun reportProcessed() {
            val processed = skippedCount + scanned
            val pct = if (totalFiles > 0) {
                processed.toDouble() / totalFiles.toDouble() * 100.0
            } else {
                100.0
            }
            updateSafScanProgress {
                it.scannedFiles = processed
                it.errorCount = errors
                it.progressPct = pct
            }
        }

        fun cancelledIncrementalResult(): String {
            updateSafScanProgress { it.isComplete = true }
            spill.abandon()
            val result = JSONObject()
            result.put("files", JSONArray())
            result.put("removedUris", JSONArray())
            result.put("skippedCount", skippedCount)
            result.put("totalFiles", totalFiles)
            result.put("error_count", errors)
            result.put("cancelled", true)
            return result.toString()
        }

        for (cue in cueFilesToScan) {
            if (safScanStopRequested(cancelled)) return cancelledIncrementalResult()

            val cueDoc = cue.doc
            val parentDir = cue.parentDir
            val cueName = cue.name
            val cueLastModified = cue.lastModified
            val cueUri = cueDoc.uri.toString()
            updateSafScanProgress { it.currentFile = cueName }

            // A transient CUE failure must not look like a deletion: keep the
            // virtual rows that already exist for this sheet. Returns whether
            // any rows survived, so their backing audio stays claimed.
            fun retainExistingCueRows(): Boolean {
                val retained = existingCueVirtualPaths[cueUri] ?: return false
                currentUris.addAll(retained)
                return retained.isNotEmpty()
            }

            var tempCuePath: String? = null
            var audioFileName: String? = null
            var audioUri: String? = null
            try {
                tempCuePath = copyUriToTemp(cueDoc.uri, ".cue", cueName)
                if (tempCuePath == null) {
                    errors++
                    reportLibraryScanError(cueUri, "Read CUE", "Failed to copy CUE file")
                    retainExistingCueRows()
                    scanned++
                    reportProcessed()
                    continue
                }

                audioFileName = extractCueAudioFileName(tempCuePath)

                val audioEntry = resolveCueAudioEntry(
                    parentDir = parentDir,
                    cueName = cueName,
                    audioFileName = audioFileName,
                    childLookupCache = safChildLookupCache,
                )

                if (audioEntry == null) {
                    reportLibraryScanError(cueUri, "Resolve CUE audio", "No audio file found for $cueName")
                    errors++
                    if (retainExistingCueRows()) {
                        audioFileName?.let {
                            unresolvedCueAudioKeys.add(unresolvedCueAudioKey(parentDir, it))
                        }
                    }
                    scanned++
                    reportProcessed()
                    continue
                }

                audioUri = audioEntry.doc.uri.toString()

                // The traversal listing already returned these values: querying
                // the document again costs a provider round trip per track.
                val audioName = audioEntry.name?.takeIf { it.isNotBlank() } ?: "audio.flac"
                val audioLastModified = audioEntry.lastModified
                val coverCacheKey = buildLibraryCoverCacheKey(
                    audioEntry.doc.uri.toString(),
                    audioLastModified,
                )

                val cueResultsJson = scanCueFromUri(
                    tempCuePath,
                    audioEntry.doc.uri,
                    audioName,
                    cueDoc.uri.toString(),
                    cueLastModified,
                    coverCacheKey,
                )

                val cueArray = JSONArray(cueResultsJson)
                for (j in 0 until cueArray.length()) {
                    val trackObj = cueArray.getJSONObject(j)
                    putFile(trackObj)
                    val virtualPath = trackObj.optString("filePath", "")
                    if (virtualPath.isNotBlank()) {
                        currentUris.add(virtualPath)
                    }
                }
                // Only a sheet that produced rows owns its audio: a failed or
                // empty parse must keep the standalone row instead of deleting
                // it in removedUris.
                if (safCueProducedRows(cueArray.length())) {
                    cueReferencedAudioUris.add(audioUri)
                }

            } catch (e: Exception) {
                errors++
                reportLibraryScanError(cueUri, "Scan CUE", e.message ?: e.javaClass.simpleName)
                if (retainExistingCueRows()) {
                    audioUri?.let { cueReferencedAudioUris.add(it) }
                    audioFileName?.let {
                        unresolvedCueAudioKeys.add(unresolvedCueAudioKey(parentDir, it))
                    }
                }
            } finally {
                try { tempCuePath?.let { File(it).delete() } } catch (_: Exception) {}
            }

            scanned++
            reportProcessed()
        }

        val pendingAudio = mutableListOf<ChangedAudio>()
        for (audio in audioFiles) {
            if (safScanStopRequested(cancelled)) return cancelledIncrementalResult()
            if (cueReferencedAudioUris.contains(audio.doc.uri.toString()) ||
                unresolvedCueAudioKey(audio.parentDir, audio.name) in unresolvedCueAudioKeys
            ) {
                scanned++
                reportProcessed()
            } else {
                pendingAudio.add(audio)
            }
        }

        val completed = runSafReadsInOrder(
            pendingAudio,
            cancelled = { safScanStopRequested(cancelled) },
            task = { audio ->
                val ext = audio.name.substringAfterLast('.', "").lowercase(Locale.ROOT)
                val fallbackExt = if (ext.isNotBlank()) ".${ext}" else null
                readAudioMetadataFromUri(
                    audio.doc.uri,
                    audio.name,
                    fallbackExt,
                    buildLibraryCoverCacheKey(audio.doc.uri.toString(), audio.lastModified),
                    onFailure = { message ->
                        reportLibraryScanError(audio.doc.uri.toString(), "Read metadata", message)
                    },
                )
            },
        ) { audio, result ->
            updateSafScanProgress { it.currentFile = audio.name }
            // A failed read aborts the incremental scan, as it did when serial.
            val metadataObj = try {
                result.getOrThrow()
            } catch (error: Exception) {
                reportLibraryScanError(audio.doc.uri.toString(), "Read metadata", error.message ?: error.javaClass.simpleName)
                // The rethrow aborts the scan; release the spill file with it.
                spill.abandon()
                throw error
            }
            if (metadataObj == null) {
                errors++
            } else {
                try {
                    val stableUri = audio.doc.uri.toString()
                    metadataObj.put("id", buildStableLibraryId(stableUri))
                    metadataObj.put("filePath", stableUri)
                    metadataObj.put("fileModTime", audio.lastModified)
                    metadataObj.put("lastModified", audio.lastModified)
                    putFile(metadataObj)
                } catch (error: Exception) {
                    errors++
                    reportLibraryScanError(audio.doc.uri.toString(), "Index track", error.message ?: error.javaClass.simpleName)
                }
            }
            scanned++
            reportProcessed()
        }
        if (!completed) return cancelledIncrementalResult()

        // Also drop standalone audio rows that a CUE sheet now owns.
        val finalRemovedUris = removalUris()

        updateSafScanProgress {
            it.isComplete = true
            it.errorCount = errors
            it.progressPct = 100.0
        }

        spill.raw("],\"removedUris\":")
        spill.raw(JSONArray(finalRemovedUris).toString())
        spill.raw(",\"skippedCount\":$skippedCount,\"totalFiles\":$totalFiles")
        spill.raw(",\"error_count\":$errors}")
        return spill.result()
    }

// A failed DocumentsProvider query must never be mistaken for a missing file.
// Unlike DocumentFile.exists(), this keeps null cursors/exceptions inconclusive.
internal fun MainActivity.safExistsBatch(urisJson: String): String {
    val result = JSONObject()
    val uris = JSONArray(urisJson)
    val accessibleTrees = mutableMapOf<String, Boolean>()
    val permissions = contentResolver.persistedUriPermissions
    val projection = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
    for (index in 0 until uris.length()) {
        val path = uris.optString(index)
        if (path.isBlank()) continue
        var status = "unknown"
        try {
            val uri = Uri.parse(path)
            val treeAccessible = if (DocumentsContract.isTreeUri(uri)) {
                val treeId = DocumentsContract.getTreeDocumentId(uri)
                val tree = DocumentsContract.buildTreeDocumentUri(uri.authority, treeId)
                accessibleTrees.getOrPut(tree.toString()) {
                    val granted = permissions.any { it.uri == tree && it.isReadPermission }
                    if (!granted) false else {
                        val root = DocumentsContract.buildDocumentUriUsingTree(tree, treeId)
                        contentResolver.query(root, projection, null, null, null)?.use {
                            it.moveToFirst()
                        } == true
                    }
                }
            } else false
            contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                // An error cursor with no rows is a failed query, not deletion.
                val failure = safListingFailureReason(
                    cursor.extras.getBoolean(DocumentsContract.EXTRA_LOADING, false),
                    cursor.extras.getString(DocumentsContract.EXTRA_ERROR),
                )
                status = if (cursor.moveToFirst()) "found"
                    else if (failure == null && treeAccessible) "missing" else "unknown"
            }
        } catch (_: Exception) {
            // Revoked permission, offline storage and provider errors: retain row.
        }
        result.put(path, status)
    }
    return result.toString()
}

/**
 * Resolve SAF file last-modified values for a list of content URIs.
 * Returns JSON object mapping uri -> lastModified (unix millis).
 */
internal fun MainActivity.getSafFileModTimes(urisJson: String): String {
        val result = JSONObject()
        val uris = try {
            JSONArray(urisJson)
        } catch (_: Exception) {
            JSONArray()
        }

        for (i in 0 until uris.length()) {
            val uriStr = uris.optString(i, "")
            if (uriStr.isBlank()) continue
            try {
                val uri = Uri.parse(uriStr)
                val doc = DocumentFile.fromSingleUri(this, uri)
                if (doc != null && doc.exists()) {
                    result.put(uriStr, doc.lastModified())
                }
            } catch (_: Exception) {}
        }

        return result.toString()
    }
