package com.amwolfstein.sistrum

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChargingStateTest {
    @Test fun batteryAndInvalidValuesDoNotPermitLibrarySweep() {
        assertFalse(ChargingState.externallyPowered(0))
        assertFalse(ChargingState.externallyPowered(-1))
    }
    @Test fun acUsbWirelessAndDockPermitSweep() {
        for (flag in listOf(1, 2, 4, 8, 3)) assertTrue(ChargingState.externallyPowered(flag))
    }
}
