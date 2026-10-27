package com.amwolfstein.sistrum

import android.app.Application
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import com.ryanheise.audioservice.AudioServicePlugin

class SpotiFlacApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        deleteLegacyPlaybackNotificationChannel(this)
        AudioServicePlugin.setFlutterEngineArguments(flutterRendererShellArgs())
    }
}

/** Runs before any UI or background audio engine creates the new playback channel. */
internal fun deleteLegacyPlaybackNotificationChannel(context: Context) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        // Deleting an absent channel is a no-op; no persisted migration key is needed.
        context.getSystemService(NotificationManager::class.java)
            .deleteNotificationChannel("com.zarz.spotiflac.playback")
    }
}
