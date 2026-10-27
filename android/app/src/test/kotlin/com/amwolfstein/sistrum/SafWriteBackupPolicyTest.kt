package com.amwolfstein.sistrum

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SafWriteBackupPolicyTest {
    private val reserve = 1L shl 20

    @Test fun backupNeedsRoomForOriginalAndReserve() {
        assertTrue(SafWriteBackupPolicy.canBackUp(100L, 100L + reserve))
        assertFalse(SafWriteBackupPolicy.canBackUp(100L, 100L + reserve - 1))
        assertFalse(SafWriteBackupPolicy.canBackUp(-1L, Long.MAX_VALUE))
        assertFalse(SafWriteBackupPolicy.canBackUp(Long.MAX_VALUE, Long.MAX_VALUE))
    }

    @Test fun emptyOriginalStillNeedsReserve() {
        assertTrue(SafWriteBackupPolicy.canBackUp(0L, reserve))
        assertFalse(SafWriteBackupPolicy.canBackUp(0L, reserve - 1))
    }

    @Test fun unknownProviderSizeCannotFailVerification() {
        assertTrue(SafWriteBackupPolicy.sizeMatches(4096L, null))
        assertTrue(SafWriteBackupPolicy.sizeMatches(4096L, -1L))
        assertTrue(SafWriteBackupPolicy.sizeMatches(4096L, 4096L))
        assertFalse(SafWriteBackupPolicy.sizeMatches(4096L, 4095L))
        assertFalse(SafWriteBackupPolicy.sizeMatches(4096L, 0L))
    }

    @Test fun rollbackMustBeVerifiedBeforeRecoveryCanBeDiscarded() {
        var stored = 4L
        assertFalse(SafWriteBackupPolicy.restoreVerified(100L, { stored = 50L }, { stored }))
        assertTrue(SafWriteBackupPolicy.restoreVerified(100L, { stored = 100L }, { stored }))
        assertFalse(SafWriteBackupPolicy.restoreVerified(100L, {}, { null }))
        assertFalse(SafWriteBackupPolicy.restoreVerified(100L, { error("disk full") }, { 100L }))
        assertFalse(SafWriteBackupPolicy.restoreVerified(100L, {}, { error("stat failed") }))
    }

    @Test fun shortOriginalBackupIsRejectedBeforeReplacement() {
        assertFalse(SafWriteBackupPolicy.sizeMatches(50L, 100L))
        assertTrue(SafWriteBackupPolicy.sizeMatches(100L, 100L))
    }

    @Test fun recoveryNameStaysInsideTheRecoveryDirectory() {
        assertEquals(
            "1700000000000-Song.mp3",
            SafWriteBackupPolicy.recoveryName(1700000000000L, "Song.mp3"),
        )
        val traversal = SafWriteBackupPolicy.recoveryName(1L, "../../etc/passwd")
        assertFalse(traversal.contains("/"))
        assertFalse(traversal.contains(".."))
        assertEquals("1-audio", SafWriteBackupPolicy.recoveryName(1L, "///"))
    }
}
