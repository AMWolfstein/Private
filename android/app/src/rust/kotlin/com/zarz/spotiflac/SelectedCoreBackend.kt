package com.zarz.spotiflac

import android.content.Context
import android.net.Uri
import com.spotiflac.backend.LocalBackend
import com.spotiflac.backend.RequestLease
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID
import org.json.JSONObject

internal fun createCoreBackend(context: Context): CoreBackend = RustCoreBackend.initialize(context)

internal suspend fun MainActivity.dispatchBackendApplication(call: MethodCall, result: MethodChannel.Result): Boolean {
    if (call.method == "cancelNativeDataJob") {
        val args = call.arguments as? Map<*, *>
        NativeDataJobs.cancel(args?.get("request_id") as? String ?: "")
        result.success(null)
        return true
    }
    val jobId = if (call.method == "runNativeDataJob") {
        (call.arguments as? Map<*, *>)?.get("request_id") as? String
            ?: error("Missing data job ID")
    } else null
    val jobLease = jobId?.let { NativeDataJobs.acquire(it) }
    val response = try {
        withContext(Dispatchers.IO) {
            when (call.method) {
                "runNativeDataJob" -> runNativeDataJobPlatform(call.arguments, checkNotNull(jobLease))


                else -> coreBackend.invokeApplication(call.method, call.arguments)
            }
        }
    } finally {
        if (jobLease != null) NativeDataJobs.release(checkNotNull(jobId), jobLease)
    }
    result.success(response)
    return true
}

internal object RustCoreBackend : CoreBackend {
    override val implementation = "rust"
    private lateinit var workspace: NativeMediaWorkspace
    private var manager: LocalBackend? = null
    private val directoryScopes = mutableMapOf<String, AutoCloseable>()
    private val logs = com.spotiflac.backend.LogBuffer()
    private var libraryCoverScope: AutoCloseable? = null
    @Volatile private var libraryCoverDirectory: File? = null

    @Synchronized
    fun initialize(context: Context): RustCoreBackend {
        if (!::workspace.isInitialized) {
            workspace = NativeMediaWorkspace(context.applicationContext.noBackupFilesDir)
        }
        if (manager == null) {
            val root = workspace.ensureDirectory()
            manager = LocalBackend(root.canonicalPath).also {
                it.setAllowedDirectories(listOf(root.canonicalPath, root.absolutePath).distinct())
            }
        }
        return this
    }

    @Synchronized
    private fun owner(): LocalBackend = checkNotNull(manager) { "Local backend is not initialized" }

    private fun directoryAliases(value: String): List<String> {
        require(File(value).isAbsolute) { "Media directories must be absolute" }
        val path = File(value).canonicalPath
        require(path != "/") { "Cannot grant the filesystem root" }
        return listOf(path, File(value).absolutePath).distinct()
    }

    @Synchronized
    override fun openMediaDirectory(path: String): AutoCloseable {
        val scope = owner().grantDirectories(directoryAliases(path))
        return object : AutoCloseable {
            private var released = false
            @Synchronized
            override fun close() {
                if (released) return
                released = true
                try { scope.release() } finally { scope.close() }
            }
        }
    }

    internal fun runDataJob(request: JSONObject, bytes: ByteArray, lease: RequestLease): String {
        if (request.optString("operation") != "library_scan_incremental") {
            return com.spotiflac.backend.runNativeDataJob(request.toString(), bytes, lease)
        }
        return withLibraryDirectories(listOf(request.getString("folder_path"))) { current ->
            val snapshot = request.optString("snapshot_path")
            val staged = if (snapshot.isEmpty()) null else workspace.createTemporaryFile("library_snapshot_", ".tsv")
            try {
                if (staged != null) {
                    File(snapshot).copyTo(staged, overwrite = true)
                    request.put("snapshot_path", staged.canonicalPath)
                }
                current.runNativeDataJob(request.toString(), bytes, lease)
            } finally { staged?.delete() }
        }
    }

    @Synchronized
    override fun shutdown() {
        // Stop and drain native work before releasing its retained file grants.
        manager?.let { it.shutdown(); it.close() }
        manager = null
        directoryScopes.values.forEach { it.close() }
        directoryScopes.clear()
        libraryCoverScope?.close()
        libraryCoverScope = null
        libraryCoverDirectory = null
    }

    override fun fileMetadataImplementation(path: String): String = "rust"

    override fun readFileMetadata(path: String, hint: String): String =
        com.spotiflac.backend.readFileMetadata(path, hint, null)



    override fun readAudioMetadata(path: String, hint: String, cacheKey: String): String {
        val descriptor = path.removePrefix("/proc/self/fd/").toIntOrNull()
        if (path.startsWith("/proc/self/fd/") && descriptor != null) {
            val directory = libraryCoverDirectory
            // Never key artwork by the descriptor number: Android reuses it.
            val key = cacheKey.trim().takeIf { it.isNotEmpty() }
            val hash = key?.codePoints()?.reduce(5381) { hash, codePoint -> hash * 33 + codePoint }
                ?.toUInt()?.toString(16)
            val cached = if (directory != null && hash != null) {
                listOf(File(directory, "cover_$hash.jpg"), File(directory, "cover_$hash.png"))
                    .firstOrNull { it.isFile }
            } else null
            val result = com.spotiflac.backend.readLibraryMetadataFromDescriptor(
                descriptor, hint, java.time.Instant.now().toString(),
                directory != null && hash != null && cached == null, null,
            )
            val metadata = JSONObject(result.metadataJson)
            var cover = cached
            if (directory != null && hash != null && result.coverBytes.isNotEmpty()) {
                try {
                    val extension = if (result.coverMime.contains("png")) "png" else "jpg"
                    val output = File(directory, "cover_$hash.$extension")
                    val staged = File.createTempFile("cover_", ".tmp", directory)
                    try {
                        staged.writeBytes(result.coverBytes)
                        check(staged.renameTo(output)) { "Could not publish library artwork" }
                        cover = output
                    } finally { staged.delete() }
                } catch (error: Exception) {
                    android.util.Log.w("SpotiFLAC", "Could not cache document artwork", error)
                }
            }
            cover?.let { metadata.put("coverPath", it.path) }
            return metadata.toString()
        }
        return withMediaFiles(listOf(path)) {
            it.readAudioMetadata(File(path).canonicalPath, hint, cacheKey, null)
        }
    }

    // Native callers have already selected/resolved these files through app or
    // SAF access. Retain only their parent directories for this operation.
    private fun <T> withMediaFiles(paths: List<String>, block: (LocalBackend) -> T): T =
        withLibraryDirectories(paths.filter { it.isNotBlank() }.map { path ->
            require(File(path).isAbsolute) { "Media paths must be absolute" }
            File(path).absoluteFile.parent!!
        }.distinct(), block)

    private fun <T> withLibraryDirectories(paths: List<String>, block: (LocalBackend) -> T): T {
        val (current, scope) = synchronized(this) {
            val current = owner()
            val aliases = paths.flatMap { directoryAliases(it) }.distinct()
            current to current.grantDirectories(aliases)
        }
        return scope.use {
            try { block(current) } finally { it.release() }
        }
    }

    @Synchronized
    override fun setLibraryCoverCacheDirectory(path: String) {
        val current = owner()
        require(path.isEmpty() || File(path).isAbsolute) { "Library cover directory must be absolute" }
        val directory = if (path.isEmpty()) null else File(path).canonicalFile
        if (directory != null) check(directory.mkdirs() || directory.isDirectory)
        val next = directory?.let { openMediaDirectory(it.path) }
        try { current.setLibraryCoverCacheDirectory(directory?.path.orEmpty()) }
        catch (error: Exception) { next?.close(); throw error }
        libraryCoverScope?.close()
        libraryCoverScope = next
        libraryCoverDirectory = directory
    }

    override fun scanLibraryFolderToNdjsonFile(folder: String, output: String): Long =
        withLibraryDirectories(listOf(folder)) { current ->
            require(File(output).isAbsolute && File(output).extension.equals("ndjson", ignoreCase = true)) {
                "Library scan output must be an absolute NDJSON path"
            }
            // Keep the
            // Rust write inside the private staging root, then publish
            // the completed result through the native app's file access.
            val staged = workspace.createTemporaryFile("library_scan_", ".ndjson")
            try {
                val count = current.scanLibraryFolderToNdjsonFile(File(folder).canonicalPath, staged.canonicalPath, null)
                check(staged.renameTo(File(output))) { "Failed to publish library scan output" }
                count.toLong()
            } finally { staged.delete() }
        }

    override fun scanLibraryFolderIncremental(folder: String, existing: String): String =
        withLibraryDirectories(listOf(folder)) {
            it.scanLibraryFolderIncremental(File(folder).canonicalPath, existing, null)
        }

    override fun scanLibraryFolderIncrementalFromSnapshot(folder: String, snapshot: String): String =
        withLibraryDirectories(listOf(folder)) { current ->
            if (snapshot.isEmpty()) current.scanLibraryFolderIncremental(File(folder).canonicalPath, "{}", null)
            else {
                val staged = workspace.createTemporaryFile("library_snapshot_", ".ndjson")
                try {
                    File(snapshot).copyTo(staged, overwrite = true)
                    current.scanLibraryFolderIncrementalFromSnapshot(File(folder).canonicalPath, staged.canonicalPath, null)
                } finally { staged.delete() }
            }
        }

    override fun getLibraryScanProgress(): String =
        synchronized(this) { manager }?.getLibraryScanProgress() ?: "{}"

    override fun cancelLibraryScan() { synchronized(this) { manager }?.cancelLibraryScan() }

    override fun pauseLibraryScan() { synchronized(this) { manager }?.pauseLibraryScan() }

    override fun resumeLibraryScan() { synchronized(this) { manager }?.resumeLibraryScan() }

    override fun parseCueSheet(path: String, audioDirectory: String): String {
        val cue = File(path).canonicalFile
        val audio = if (audioDirectory.isEmpty()) cue.parentFile!! else File(audioDirectory).canonicalFile
        return withLibraryDirectories(listOf(cue.parent, audio.path)) {
            it.parseCueFileJson(cue.path, audio.path, null)
        }
    }

    override fun parseCueSheetWithResolvedAudio(path: String, audioPath: String): String {
        val cue = File(path).canonicalFile
        return withLibraryDirectories(listOf(cue.parent)) {
            it.parseCueFileJsonWithResolvedAudio(cue.path, audioPath, null)
        }
    }



    override fun scanCueForLibraryWithResolvedAudio(path: String, audioPath: String, audioName: String, virtualPrefix: String, modTime: Long, cacheKey: String): String {
        val cue = File(path).canonicalFile
        fun scan(descriptor: Int): String {
            // Artwork remains optional, as in the filesystem CUE scanner.
            // A cover extraction failure must not discard valid CUE rows.
            val coverPath = try {
                JSONObject(readAudioMetadata("/proc/self/fd/$descriptor", audioName, cacheKey)).optString("coverPath", "")
            } catch (error: Exception) {
                if (error is java.util.concurrent.CancellationException) throw error
                android.util.Log.w("SpotiFLAC", "Could not read CUE artwork", error)
                ""
            }
            return withLibraryDirectories(listOf(requireNotNull(cue.parent))) {
                it.scanCueFileForLibraryFromDescriptor(
                    cue.path, descriptor, audioName, virtualPrefix, modTime,
                    coverPath, java.time.Instant.now().toString(), null,
                )
            }
        }
        val descriptor = audioPath.removePrefix("/proc/self/fd/").toIntOrNull()
        if (audioPath.startsWith("/proc/self/fd/") && descriptor != null) return scan(descriptor)
        return android.os.ParcelFileDescriptor.open(File(audioPath), android.os.ParcelFileDescriptor.MODE_READ_ONLY).use {
            scan(it.fd)
        }
    }

    override fun editFileMetadata(path: String, metadataJson: String): String {
        val cover = if (metadataJson.trim() == "null") "" else JSONObject(metadataJson).optString("cover_path", "")
        return withMediaFiles(listOf(path, cover)) {
            it.editFileMetadata(File(path).canonicalPath, metadataJson, null)
        }
    }

    private fun mediaPath(path: String): String = if (path.isEmpty()) "" else File(path).canonicalPath



    override fun extractCoverToFile(audioPath: String, outputPath: String, hint: String) {
        val descriptor = if (audioPath.startsWith("/proc/self/fd/")) {
            audioPath.removePrefix("/proc/self/fd/").toIntOrNull()
        } else null
        if (descriptor != null) {
            val artwork = com.spotiflac.backend.extractCoverFromDescriptor(
                descriptor, hint, null,
            )
            check(artwork.isNotEmpty()) { "No embedded artwork" }
            val output = File(outputPath)
            val staged = File.createTempFile("cover_", ".tmp", output.parentFile)
            try {
                staged.writeBytes(artwork)
                check(staged.renameTo(output)) { "Could not publish artwork" }
            } finally { staged.delete() }
            return
        }
        withMediaFiles(listOf(audioPath, outputPath)) {
            it.extractCoverToFile(mediaPath(audioPath), mediaPath(outputPath), null)
        }
    }

    override fun writeM4aFreeformTags(path: String, metadataJson: String): String =
        withMediaFiles(listOf(path)) { it.writeM4aFreeformTags(mediaPath(path), metadataJson, null) }








    // Local operations retain no provider caches or network connections.
    override fun releaseIdleResources() {}
    override fun releaseMemoryUnderPressure() {}

    override fun createTemporaryMediaFile(context: Context, prefix: String, suffix: String): File {
        owner()
        return workspace.createTemporaryFile(prefix, suffix)
    }

    override fun invokeApplication(method: String, arguments: Any?): Any? {
        val args = arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        fun string(key: String, default: String = "") = args[key] as? String ?: default
        return when (method) {
            "acquireMediaDirectory" -> synchronized(this) {
                val scope = openMediaDirectory(string("path"))
                val token = UUID.randomUUID().toString()
                directoryScopes[token] = scope
                token
            }
            "releaseMediaDirectory" -> synchronized(this) {
                directoryScopes.remove(string("token"))?.close()
                null
            }
            "cancelNativeDataJob" -> { NativeDataJobs.cancel(string("request_id")); null }
            "getLogsSince" -> logs.since((args["index"] as? Number)?.toLong() ?: 0L)
            "clearLogs" -> { logs.clear(); null }
            "setLoggingEnabled" -> { logs.setEnabled(args["enabled"] as? Boolean ?: false); null }



            else -> error("Unknown local backend method: $method")
        }
    }



}
