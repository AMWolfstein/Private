package com.zarz.spotiflac

import android.content.Context
import java.io.File

/** Native boundary for the local, offline player. */
internal interface CoreBackend {
    val implementation: String
    fun invokeApplication(method: String, arguments: Any?): Any? = error("Unknown local backend method: $method")
    fun shutdown()


    fun fileMetadataImplementation(path: String): String
    fun readFileMetadata(path: String, hint: String): String

    fun readAudioMetadata(path: String, hint: String, cacheKey: String): String
    fun setLibraryCoverCacheDirectory(path: String)
    fun scanLibraryFolderToNdjsonFile(folder: String, output: String): Long
    fun scanLibraryFolderIncremental(folder: String, existing: String): String
    fun scanLibraryFolderIncrementalFromSnapshot(folder: String, snapshot: String): String
    fun getLibraryScanProgress(): String
    fun cancelLibraryScan()
    fun pauseLibraryScan()
    fun resumeLibraryScan()
    fun parseCueSheet(path: String, audioDirectory: String): String
    fun parseCueSheetWithResolvedAudio(path: String, audioPath: String): String

    fun scanCueForLibraryWithResolvedAudio(path: String, audioPath: String, audioName: String, virtualPrefix: String, modTime: Long, cacheKey: String): String
    fun editFileMetadata(path: String, metadataJson: String): String

    fun extractCoverToFile(audioPath: String, outputPath: String, hint: String = "")
    fun writeM4aFreeformTags(path: String, metadataJson: String): String



    fun createTemporaryMediaFile(context: Context, prefix: String, suffix: String): File
    fun openMediaDirectory(path: String): AutoCloseable
    fun releaseIdleResources()
    fun releaseMemoryUnderPressure()
}
