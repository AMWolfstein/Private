package com.amwolfstein.sistrum

import com.amwolfstein.sistrum.DisplayRefreshRatePolicy.Mode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DisplayRefreshRatePolicyTest {
    // Two resolutions, each at 60, 90 and 120 Hz, like a phone with a
    // resolution setting.
    private val fhd60 = Mode(1, 1080, 2400, 60.0f)
    private val fhd90 = Mode(2, 1080, 2400, 90.0f)
    private val fhd120 = Mode(3, 1080, 2400, 120.0f)
    private val hd60 = Mode(4, 720, 1600, 60.0f)
    private val hd120 = Mode(5, 720, 1600, 120.0f)
    private val modes = listOf(fhd60, fhd90, fhd120, hd60, hd120)

    @Test
    fun offersOnlyRatesAtTheCurrentResolution() {
        assertEquals(listOf(60, 90, 120), DisplayRefreshRatePolicy.supportedRates(modes, fhd60))
        assertEquals(listOf(60, 120), DisplayRefreshRatePolicy.supportedRates(modes, hd120))
    }

    @Test
    fun systemDefaultRequestsNoMode() {
        assertNull(DisplayRefreshRatePolicy.modeFor(modes, fhd60, 0))
    }

    @Test
    fun choosesTheModeAtTheSameResolution() {
        assertEquals(fhd60, DisplayRefreshRatePolicy.modeFor(modes, fhd120, 60))
        assertEquals(fhd90, DisplayRefreshRatePolicy.modeFor(modes, fhd60, 90))
        assertEquals(fhd120, DisplayRefreshRatePolicy.modeFor(modes, fhd60, 120))
        assertEquals(hd120, DisplayRefreshRatePolicy.modeFor(modes, hd60, 120))
    }

    @Test
    fun anUnsupportedRateRequestsNothing() {
        // 90 Hz exists only at the other resolution.
        assertNull(DisplayRefreshRatePolicy.modeFor(modes, hd60, 90))
        assertNull(DisplayRefreshRatePolicy.modeFor(modes, fhd60, 144))
    }

    @Test
    fun fractionalRatesMatchTheirWholeNumber() {
        val ntsc = Mode(7, 1080, 2400, 59.94f)
        val list = listOf(ntsc, fhd120)
        assertEquals(listOf(60, 120), DisplayRefreshRatePolicy.supportedRates(list, ntsc))
        assertEquals(ntsc, DisplayRefreshRatePolicy.modeFor(list, fhd120, 60))
        assertTrue(DisplayRefreshRatePolicy.rateMatches(59.94f, 60))
        assertFalse(DisplayRefreshRatePolicy.rateMatches(90f, 120))
        assertFalse(DisplayRefreshRatePolicy.rateMatches(60f, 0))
    }

    @Test
    fun theClosestModeWinsAndTiesTakeTheLowerId() {
        val exact = Mode(9, 1080, 2400, 60.0f)
        val near = Mode(8, 1080, 2400, 60.5f)
        assertEquals(exact, DisplayRefreshRatePolicy.modeFor(listOf(near, exact), exact, 60))
        val twin = Mode(10, 1080, 2400, 60.0f)
        assertEquals(exact, DisplayRefreshRatePolicy.modeFor(listOf(twin, exact), exact, 60))
    }
}
