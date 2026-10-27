package com.amwolfstein.sistrum

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PlaybackNotificationChannelTest {
    @Test
    fun startupCleanupDeletesOnlyLegacyPlaybackChannelAndIsIdempotent() {
        assumeTrue(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val manager = context.getSystemService(NotificationManager::class.java)
        val legacyId = "com.amwolfstein.sistrum.playback"
        val currentId = "com.amwolfstein.sistrum.playback"
        val previousCurrent = manager.getNotificationChannel(currentId)
        try {
            manager.createNotificationChannel(
                NotificationChannel(legacyId, "Playback", NotificationManager.IMPORTANCE_LOW),
            )
            manager.createNotificationChannel(
                NotificationChannel(currentId, "Playback", NotificationManager.IMPORTANCE_LOW),
            )
            val current = manager.getNotificationChannel(currentId)
            assertNotNull(manager.getNotificationChannel(legacyId))

            deleteLegacyPlaybackNotificationChannel(context)
            deleteLegacyPlaybackNotificationChannel(context)

            assertNull(manager.getNotificationChannel(legacyId))
            assertEquals(current, manager.getNotificationChannel(currentId))
        } finally {
            manager.deleteNotificationChannel(legacyId)
            if (previousCurrent == null) manager.deleteNotificationChannel(currentId)
        }
    }
}
