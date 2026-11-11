package com.zarz.mornye

import org.junit.Assert.*
import org.junit.Test

class ProviderUpdateReadinessTest {
    @Test fun updatesStartOnlyAfterPolicyConfiguration() {
        val events = mutableListOf<String>()
        configureBackendAndStartUpdates(Any(),
            configure = { events += "directories"; events += "network"; events += "runtime"; events += "fallbacks" },
            startUpdates = { events += "updates" }, updateFailure = { _, _ -> fail("unexpected failure") },
            dispose = { fail("unexpected disposal") })
        assertEquals(listOf("directories", "network", "runtime", "fallbacks", "updates"), events)
    }

    @Test fun failedPolicySetupDisposesOwnerAndNeverStartsUpdates() {
        val expected = IllegalStateException("policy rejected")
        val events = mutableListOf<String>()
        try {
            configureBackendAndStartUpdates(Any(), configure = { throw expected },
                startUpdates = { fail("updates started before readiness") }, updateFailure = { _, _ -> fail("wrong failure") },
                dispose = { events += "disposed" })
            fail("policy error swallowed")
        } catch (error: IllegalStateException) {
            assertSame(expected, error)
        }
        assertEquals(listOf("disposed"), events)
    }

    @Test fun optionalUpdateSchedulingFailureKeepsConfiguredOwnerUsable() {
        val events = mutableListOf<String>()
        configureBackendAndStartUpdates(Any(), configure = { events += "ready" },
            startUpdates = { throw IllegalStateException("worker unavailable") },
            updateFailure = { _, error -> events += error.message!!; throw IllegalStateException("logging unavailable") },
            dispose = { fail("configured owner disposed for optional update failure") })
        events += "usable"
        assertEquals(listOf("ready", "worker unavailable", "usable"), events)
    }
}
