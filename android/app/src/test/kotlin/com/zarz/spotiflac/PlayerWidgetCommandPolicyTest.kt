package com.zarz.spotiflac

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlayerWidgetCommandPolicyTest {
    @Test fun acceptsOnlyExistingTransportCommands() {
        for (command in listOf("toggle", "next", "previous")) {
            assertTrue(command, PlayerWidgetCommandPolicy.isAllowed(command))
        }
    }

    @Test fun rejectsUnknownAndMalformedActivityExtras() {
        for (command in listOf(null, "", "play", "stop", "delete", "Toggle", " next", "next ", "next\u0000")) {
            assertFalse(command.toString(), PlayerWidgetCommandPolicy.isAllowed(command))
        }
    }
}
