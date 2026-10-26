package com.zarz.spotiflac

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SafScanPolicyTest {
    @Test fun cueHeaderStreamsPastLongPreamblesAndStopsAtFile() {
        val lines = sequence {
            repeat(1024) { yield("REM " + "x".repeat(80)) }
            yield("FILE \"different audio.flac\" WAVE")
            error("The FILE line is enough; do not consume the remainder")
        }
        assertEquals("different audio.flac", cueAudioFileName(lines.asIterable()))
    }

    @Test fun providerErrorAndLoadingCursorsAreNotAuthoritative() {
        assertEquals("provider-loading", safListingFailureReason(loading = true, error = null))
        assertEquals(
            "provider-error: failed to connect",
            safListingFailureReason(loading = false, error = "failed to connect"),
        )
        assertNull(safListingFailureReason(loading = false, error = null))
        assertNull(safListingFailureReason(loading = false, error = "  "))
    }

    @Test fun zeroTimestampsAlwaysForceARescan() {
        assertTrue(safFileChanged(existingModified = 0L, currentModified = 0L))
        assertTrue(safFileChanged(existingModified = 0L, currentModified = 123L))
        assertTrue(safFileChanged(existingModified = 123L, currentModified = 0L))
        assertTrue(safFileChanged(existingModified = null, currentModified = 123L))
        assertTrue(safFileChanged(existingModified = 123L, currentModified = 124L))
        assertFalse(safFileChanged(existingModified = 123L, currentModified = 123L))
    }

    @Test fun resumedRowsFollowTheirBackingCueDocument() {
        val current = setOf("content://tree/album/cue.cue", "content://tree/album/a.flac")

        assertFalse(safScanRowIsStale("content://tree/album/a.flac", current))
        assertFalse(safScanRowIsStale("content://tree/album/cue.cue#track1", current))
        assertTrue(safScanRowIsStale("content://tree/album/cue.cue#track2", emptySet()))
        assertTrue(safScanRowIsStale("content://tree/album/deleted.flac", current))
        assertTrue(safScanRowIsStale("", current))
    }

    @Test fun onlyATrailingCueTrackSuffixIsVirtual() {
        assertEquals(
            "content://tree/album/cue.cue",
            safCueBasePath("content://tree/album/cue.cue#track12"),
        )
        assertNull(safCueBasePath("content://tree/album/cue.cue"))
        // A real file may contain "#track" without being a CUE row.
        assertNull(safCueBasePath("content://tree/album/song#track2.flac"))
        assertNull(safCueBasePath("#track1"))
        assertFalse(
            safScanRowIsStale(
                "content://tree/album/song#track2.flac",
                setOf("content://tree/album/song#track2.flac"),
            ),
        )
    }

    @Test fun cueReferencedAudioDropsItsStandaloneRow() {
        val removed = safReferencedStandaloneUris(
            existingUris = listOf("content://a.flac", "content://b.flac", "content://c.cue#track1"),
            cueReferencedUris = listOf("content://a.flac", "content://b.flac"),
        )
        assertEquals(setOf("content://a.flac", "content://b.flac"), removed)
    }

    @Test fun emptyListingClearsOnlyASourceWithoutRows() {
        // A first scan of an audio-free folder is authoritative.
        assertFalse(
            safEmptyListingIsUntrusted(
                listedFiles = 0,
                resumeHasRows = false,
                sourceHasRows = false,
            ),
        )
        // Either resume state or an indexed source makes it inconclusive.
        assertTrue(
            safEmptyListingIsUntrusted(
                listedFiles = 0,
                resumeHasRows = true,
                sourceHasRows = false,
            ),
        )
        assertTrue(
            safEmptyListingIsUntrusted(
                listedFiles = 0,
                resumeHasRows = false,
                sourceHasRows = true,
            ),
        )
        assertTrue(
            safEmptyListingIsUntrusted(
                listedFiles = 0,
                resumeHasRows = true,
                sourceHasRows = true,
            ),
        )
        assertFalse(
            safEmptyListingIsUntrusted(
                listedFiles = 3,
                resumeHasRows = true,
                sourceHasRows = true,
            ),
        )
    }

    @Test fun persistFallsBackToReadOnlyWhenNoFlagsAreReported() {
        // Reported read+write still retries read-only if the provider refuses
        // to persist the wider grant.
        assertEquals(
            listOf(3, 1),
            safTreePersistFlags(reportedFlags = 3, readFlag = 1, writeFlag = 2),
        )
        assertEquals(
            listOf(1),
            safTreePersistFlags(reportedFlags = 1, readFlag = 1, writeFlag = 2),
        )
        assertEquals(
            listOf(3, 1),
            safTreePersistFlags(reportedFlags = 0, readFlag = 1, writeFlag = 2),
        )
        assertEquals(
            listOf(3, 1),
            safTreePersistFlags(reportedFlags = 4, readFlag = 1, writeFlag = 2),
        )
        // A write-only grant cannot scan after a restart, so it is never
        // persisted as-is.
        assertEquals(
            listOf(3, 1),
            safTreePersistFlags(reportedFlags = 2, readFlag = 1, writeFlag = 2),
        )
    }

    @Test fun cueAudioFileNameHandlesQuotedUnquotedAndBomHeaders() {
        assertEquals(
            "album.flac",
            cueAudioFileName(listOf("REM comment", "FILE \"album.flac\" WAVE")),
        )
        assertEquals(
            "Artist - Album.flac",
            cueAudioFileName(listOf("file \"Artist - Album.flac\" WAVE")),
        )
        assertEquals(
            "album.flac",
            cueAudioFileName(listOf("FILE album.flac WAVE")),
        )
        assertEquals(
            "my album.flac",
            cueAudioFileName(listOf("FILE my album.flac WAVE")),
        )
        assertEquals(
            "album.flac",
            cueAudioFileName(listOf("\uFEFFFILE \"album.flac\" WAVE")),
        )
        assertEquals(
            "album.flac",
            cueAudioFileName(listOf("FILE \"C:\\\\Music\\\\album.flac\" WAVE")),
        )
        // A comment that merely mentions FILE is not a header.
        assertNull(cueAudioFileName(listOf("REM FILE is missing", "TRACK 01 AUDIO")))
        assertNull(cueAudioFileName(emptyList()))
    }

    @Test fun aMalformedSheetDoesNotHideItsBackingAudio() {
        // No rows: the audio must be indexed as a standalone file.
        assertFalse(safCueProducedRows(rowCount = 0))
        assertTrue(safCueProducedRows(rowCount = 1))
        assertTrue(safCueProducedRows(rowCount = 12))
    }

    @Test fun cueFailuresKeepEveryExistingVirtualTrack() {
        val grouped = cueVirtualPathsByCue(
            listOf(
                "content://tree/album/cue.cue#track1",
                "content://tree/album/cue.cue#track2",
                "content://tree/album/other.cue#track1",
                "content://tree/album/song.flac",
            ),
        )

        assertEquals(
            listOf("content://tree/album/cue.cue#track1", "content://tree/album/cue.cue#track2"),
            grouped["content://tree/album/cue.cue"],
        )
        assertEquals(
            listOf("content://tree/album/other.cue#track1"),
            grouped["content://tree/album/other.cue"],
        )
        assertNull(grouped["content://tree/album/song.flac"])
    }
}
