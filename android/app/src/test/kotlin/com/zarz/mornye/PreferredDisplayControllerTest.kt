package com.zarz.mornye

import org.junit.Assert.*
import org.junit.Test

class PreferredDisplayControllerTest {
    private val current = PreferredMode(1, 1080, 2400, 120f)
    @Test fun selects60AtCurrentResolution() {
        val target = PreferredMode(3, 1080, 2400, 60f)
        assertEquals(target, preferred60Mode(listOf(current, PreferredMode(2, 720, 1600, 60f), target), current))
    }
    @Test fun unsupportedDoesNotSelectDifferentResolutionOr90Hz() {
        assertNull(preferred60Mode(listOf(current, PreferredMode(2, 720, 1600, 60f), PreferredMode(3, 1080, 2400, 90f)), current))
    }
    @Test fun prefersClosestRateAndSupportsFractional60() {
        val fractional = PreferredMode(2, 1080, 2400, 59.94f)
        assertEquals(fractional, preferred60Mode(listOf(fractional), current))
        val exact = PreferredMode(3, 1080, 2400, 60f)
        assertEquals(exact, preferred60Mode(listOf(fractional, exact), current))
    }
    @Test fun transitionsAreTimestampedBoundedAndResettable() {
        val history = DisplayModeHistory()
        history.observe(1, 60f, 100L)
        history.observe(1, 60f, 101L)
        assertEquals(0, history.transitions)
        history.observe(2, 120f, 102L)
        assertEquals(1, history.transitions)
        assertEquals(102L, history.changes.first()["at_ms"])
        for (i in 3..50) history.observe(i, 60f, i.toLong())
        assertEquals(32, history.changes.size)
        assertEquals(49, history.transitions)
        history.reset()
        assertEquals(0, history.transitions)
        assertTrue(history.changes.isEmpty())
        history.observe(50, 60f, 200L)
        assertEquals(0, history.transitions)
    }
}
