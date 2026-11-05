package com.amwolfstein.sistrum

import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Pure display-mode selection for the user's refresh-rate preference. Kept
 * free of Android types so host unit tests can cover it.
 */
object DisplayRefreshRatePolicy {
    /** A display mode as `Display.Mode` reports it. */
    data class Mode(val id: Int, val width: Int, val height: Int, val refreshHz: Float)

    /** How far a mode's rate may sit from a whole-number choice (59.94 counts as 60). */
    private const val RATE_TOLERANCE_HZ = 1.0f

    /**
     * The whole-number refresh rates offered for [current]'s resolution,
     * ascending. Modes at another resolution are never offered, so choosing
     * one never changes the resolution.
     */
    fun supportedRates(modes: List<Mode>, current: Mode): List<Int> =
        modes.asSequence()
            .filter { sameResolution(it, current) && it.refreshHz > 0f }
            .map { it.refreshHz.roundToInt() }
            .distinct()
            .sorted()
            .toList()

    /**
     * The mode to request for [preferredHz] at [current]'s resolution, or
     * null when the preference is System Default (0 or less) or no mode
     * at that resolution has the rate.
     */
    fun modeFor(modes: List<Mode>, current: Mode, preferredHz: Int): Mode? {
        if (preferredHz <= 0) return null
        return modes
            .filter { sameResolution(it, current) }
            .filter { abs(it.refreshHz - preferredHz) <= RATE_TOLERANCE_HZ }
            .minWithOrNull(compareBy<Mode> { abs(it.refreshHz - preferredHz) }.thenBy { it.id })
    }

    /** True when an active rate matches a whole-number choice. */
    fun rateMatches(activeHz: Float, preferredHz: Int): Boolean =
        preferredHz > 0 && abs(activeHz - preferredHz) <= RATE_TOLERANCE_HZ

    private fun sameResolution(a: Mode, b: Mode): Boolean =
        a.width == b.width && a.height == b.height
}
