package com.amwolfstein.sistrum

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class NativePlaybackFailureTest {
    private class MissingNative {
        companion object {
            init { throw UnsatisfiedLinkError("missing test library") }
            fun touch() = Unit
        }
    }

    @Test fun firstLoadAndPoisonedInitializerReachExceptionHandler() {
        repeat(2) {
            var handled = false
            try {
                nativePlaybackCall { MissingNative.touch() }
                fail("Native initialization must fail")
            } catch (error: Exception) {
                handled = true
                assertEquals("Native audio unavailable", error.message)
                assertTrue(error.cause is LinkageError)
            }
            assertTrue("Playback's Exception handler must contain the load failure", handled)
        }
    }

    @Test fun missingJniSymbolAndInitializerErrorKeepTheirCause() {
        for (failure in listOf(UnsatisfiedLinkError("missing JNI symbol"),
            ExceptionInInitializerError(IllegalStateException("loader failed")))) {
            try {
                nativePlaybackCall { throw failure }
                fail("Linkage failure must be converted")
            } catch (error: Exception) {
                assertSame(failure, error.cause)
            }
        }
    }

    @Test fun normalResultsAndExceptionsAreUnchanged() {
        assertEquals(42, nativePlaybackCall { 42 })
        val failure = IllegalArgumentException("bad source")
        try {
            nativePlaybackCall { throw failure }
            fail("Source error must propagate")
        } catch (error: Exception) {
            assertSame(failure, error)
        }
    }

    @Test fun unrelatedVmErrorsAreNotSwallowed() {
        val failure = OutOfMemoryError("test only")
        try {
            nativePlaybackCall { throw failure }
            fail("VM error must propagate")
        } catch (error: OutOfMemoryError) {
            assertSame(failure, error)
        }
    }
}
