package com.amwolfstein.sistrum

internal enum class PlayerWidgetLayout { WIDE, COMPACT, STANDARD }

/** Keep the wide cover and three controls from squeezing short, narrow widgets. */
internal object PlayerWidgetLayoutPolicy {
    fun select(width: Int, height: Int): PlayerWidgetLayout = when {
        width >= 340 && height < 240 -> PlayerWidgetLayout.WIDE
        width < 200 || height < 240 -> PlayerWidgetLayout.COMPACT
        else -> PlayerWidgetLayout.STANDARD
    }
}
