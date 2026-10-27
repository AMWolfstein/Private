package com.amwolfstein.sistrum

import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SafDocumentLookupTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val authority = "com.sistrum.test.documents.lookup"
    private val controlUri = Uri.parse("content://$authority.control")
    private val treeUri = DocumentsContract.buildTreeDocumentUri(authority, "root")

    private fun reset(count: Int = 0, mode: String = "normal", failFinalRename: Boolean = false): DocumentFile {
        context.contentResolver.call(controlUri, "lookup.reset", null, Bundle().apply {
            putInt("count", count)
            putString("mode", mode)
            putBoolean("failFinalRename", failFinalRename)
            putString("targetPackage", context.packageName)
        })
        return requireNotNull(DocumentFile.fromTreeUri(context, treeUri))
    }

    private fun stats() = requireNotNull(context.contentResolver.call(controlUri, "lookup.stats", null, null))

    private fun clearCounters() {
        context.contentResolver.call(controlUri, "lookup.clearCounters", null, null)
    }

    @Test
    fun cueSiblingLookupBatchesCandidatesAndPreservesPriority() {
        val parent = reset(count = 2000)
        val declared = findSafCueAudioSibling(context, parent, "Song.cue", "Track 1999.flac")
        assertEquals("child:1999", DocumentsContract.getDocumentId(requireNotNull(declared).uri))
        assertEquals(1, stats().getInt("children"))
        assertEquals(0, stats().getInt("documents"))

        clearCounters()
        val fallback = findSafCueAudioSibling(context, parent, "Song.cue", "missing.flac")
        assertEquals("original", DocumentsContract.getDocumentId(requireNotNull(fallback).uri))
        assertEquals(1, stats().getInt("children"))
        assertEquals(0, stats().getInt("documents"))

        assertTrue(fallback.renameTo("Song.FLAC"))
        clearCounters()
        assertEquals(fallback.uri, findSafCueAudioSibling(context, parent, "Song.cue", null)?.uri)
        assertEquals(1, stats().getInt("children"))
        assertEquals(0, stats().getInt("documents"))

        clearCounters()
        assertNull(findSafCueAudioSibling(context, parent, "Missing.cue", null))
        assertEquals(1, stats().getInt("children"))
        assertEquals(0, stats().getInt("documents"))
    }

    @Test
    fun projectedBatchReplacesThousandsOfNameQueriesAndClosesItsCursor() {
        val parent = reset(count = 2000)
        assertNull(parent.findFile("missing.flac"))
        assertEquals(1, stats().getInt("children"))
        assertEquals(2002, stats().getInt("documents"))
        clearCounters()

        val found = findSafChildren(context, parent, setOf("Track 0.flac", "Track 1999.flac", "missing.flac"))
        assertEquals(setOf("Track 0.flac", "Track 1999.flac"), found.keys)
        assertEquals(1, stats().getInt("children"))
        assertEquals(0, stats().getInt("documents"))
        assertEquals(1, stats().getInt("closed"))
        clearCounters()
        assertNull(findSafChild(context, parent, "missing.flac"))
        assertEquals(1, stats().getInt("children"))
        assertEquals(0, stats().getInt("documents"))
        clearCounters()
        assertTrue(findSafChildren(context, parent, emptySet()).isEmpty())
        assertEquals(0, stats().getInt("children"))
    }

    @Test
    fun nestedOpaqueIdsUnicodeAndRenameKeepTheChildDocument() {
        val parent = reset()
        val directory = requireNotNull(findSafChild(context, parent, "音楽 🎵"))
        assertEquals("nested:音楽/opaque", DocumentsContract.getDocumentId(directory.uri))
        assertTrue(directory.isDirectory)
        val child = requireNotNull(findSafChild(context, directory, "歌 🎵.flac"))
        val oldUri = child.uri
        assertTrue(child.renameTo("Renamed.flac"))
        assertNotEquals(oldUri, child.uri)
        assertEquals("Renamed.flac", child.name)
        assertEquals(child.uri, findSafChild(context, directory, "Renamed.flac")?.uri)
        assertNull(findSafChild(context, parent, "Renamed.flac"))
        assertNotNull(directory.createDirectory("Created"))
    }





    @Test
    fun unsupportedProjectionNullCursorAndMissingColumnUseLegacyLookup() {
        for (mode in listOf("throw", "null", "missing")) {
            val parent = reset(count = 3, mode = mode)
            val found = requireNotNull(findSafChild(context, parent, "Song.flac"))
            assertEquals("original", DocumentsContract.getDocumentId(found.uri))
            assertEquals(2, stats().getInt("children"))
            assertEquals(5, stats().getInt("documents"))
            assertEquals(if (mode == "missing") 7 else 6, stats().getInt("closed"))
        }
    }

    @Test
    fun rawDocumentFileRetainsLegacyBehavior() {
        val directory = File(context.cacheDir, "lookup-raw").apply { mkdirs() }
        try {
            File(directory, "local.flac").writeText("audio")
            val found = findSafChild(context, DocumentFile.fromFile(directory), "local.flac")
            assertEquals("local.flac", found?.name)
        } finally {
            directory.deleteRecursively()
        }
    }






}
