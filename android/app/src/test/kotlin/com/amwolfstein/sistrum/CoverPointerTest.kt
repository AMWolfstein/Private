package com.amwolfstein.sistrum

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class CoverPointerTest {
    private val contentName = "cover_" + "a".repeat(64) + ".jpg"

    private fun directory(): File =
        Files.createTempDirectory("cover-pointer").toFile().also { it.deleteOnExit() }

    @Test fun theSameKeyAlwaysNamesTheSamePointer() {
        val name = coverPointerName("content://tree/song.flac|1700000000000")
        assertEquals(name, coverPointerName("content://tree/song.flac|1700000000000"))
        assertTrue(name.startsWith("cover_"))
        assertTrue(name.endsWith(".id"))
        assertEquals(6 + 64 + 3, name.length)
        assertTrue(name.drop(6).dropLast(3).all { it in '0'..'9' || it in 'a'..'f' })
        assertFalse(name == coverPointerName("content://tree/song.flac|1700000000001"))
    }

    @Test fun thePointerPayloadIsAValidatedContentName() {
        assertEquals(contentName, coverPointerTargetName("$contentName\n"))
        assertNull(coverPointerTargetName("cover_" + "A".repeat(64) + ".jpg"))
        assertNull(coverPointerTargetName("cover_" + "a".repeat(63) + ".jpg"))
        assertNull(coverPointerTargetName("cover_" + "a".repeat(64) + ".gif"))
        // A corrupt pointer must never address anything outside the cache.
        assertNull(coverPointerTargetName("../cover_" + "a".repeat(64) + ".jpg"))
        assertNull(coverPointerTargetName("/tmp/$contentName"))
        assertNull(coverPointerTargetName(""))
    }

    @Test fun aPointerResolvesOnlyToAnExistingNonEmptyFile() {
        val directory = directory()
        val pointer = File(directory, coverPointerName("song|1"))
        writeCoverPointer(pointer, contentName)
        assertNull(readCoverPointer(pointer, directory))

        val target = File(directory, contentName)
        target.writeBytes(byteArrayOf(1, 2, 3))
        assertEquals(target, readCoverPointer(pointer, directory))

        target.writeBytes(ByteArray(0))
        assertNull(readCoverPointer(pointer, directory))
    }

    @Test fun anUnreadablePointerIsIgnored() {
        val directory = directory()
        assertNull(readCoverPointer(File(directory, "missing.id"), directory))
        val corrupt = File(directory, coverPointerName("song|2"))
        corrupt.writeText("not a cover name")
        assertNull(readCoverPointer(corrupt, directory))
    }

    @Test fun writingAPointerReplacesItWithoutLeavingTemporaryFiles() {
        val directory = directory()
        val pointer = File(directory, coverPointerName("song|3"))
        val other = "cover_" + "b".repeat(64) + ".png"
        writeCoverPointer(pointer, contentName)
        writeCoverPointer(pointer, other)
        assertEquals(other, pointer.readText())
        assertEquals(
            listOf(pointer.name),
            directory.listFiles()!!.map { it.name }.sorted(),
        )
    }
}
