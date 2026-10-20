package com.zarz.spotiflac

import org.junit.Assert.assertEquals
import org.junit.Test

class PlayerWidgetLayoutPolicyTest {
    @Test fun sizesKeepControlsUsable() {
        assertEquals(PlayerWidgetLayout.COMPACT, PlayerWidgetLayoutPolicy.select(240, 150))
        assertEquals(PlayerWidgetLayout.COMPACT, PlayerWidgetLayoutPolicy.select(180, 300))
        assertEquals(PlayerWidgetLayout.WIDE, PlayerWidgetLayoutPolicy.select(340, 150))
        assertEquals(PlayerWidgetLayout.STANDARD, PlayerWidgetLayoutPolicy.select(340, 240))
        assertEquals(PlayerWidgetLayout.COMPACT, PlayerWidgetLayoutPolicy.select(0, 0))
    }
}
