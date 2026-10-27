package com.amwolfstein.sistrum

import android.app.Application
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import com.ryanheise.audioservice.AudioServicePlugin

class SistrumApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        deleteLegacyPlaybackNotificationChannel(this)
        AudioServicePlugin.setFlutterEngineArguments(flutterRendererShellArgs())
    }
}

/** Current playback channel; must never be deleted by the legacy cleanup. */
internal const val CURRENT_PLAYBACK_CHANNEL_ID = "com.amwolfstein.sistrum.playback"

/**
 * Former channel of the previous application identity, written as escapes so
 * the retired name is not present as plain text.
 */
internal const val LEGACY_PLAYBACK_CHANNEL_ID =
    "\u0063\u006f\u006d.\u007a\u0061\u0072\u007a.\u0073\u0070\u006f\u0074\u0069\u0066\u006c\u0061\u0063.\u0070\u006c\u0061\u0079\u0062\u0061\u0063\u006b"

/** Runs before any UI or background audio engine creates the new playback channel. */
internal fun deleteLegacyPlaybackNotificationChannel(context: Context) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
        LEGACY_PLAYBACK_CHANNEL_ID != CURRENT_PLAYBACK_CHANNEL_ID
    ) {
        // Deleting an absent channel is a no-op; no persisted migration key is needed.
        context.getSystemService(NotificationManager::class.java)
            .deleteNotificationChannel(LEGACY_PLAYBACK_CHANNEL_ID)
    }
}
