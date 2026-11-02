package com.amwolfstein.sistrum

import android.app.Application
import com.ryanheise.audioservice.AudioServicePlugin

class SistrumApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        try {
            AppCrashReporter.initialize(this)
        } catch (error: Exception) {
            android.util.Log.w("AppCrashReporter", "Crash reporting initialization unavailable", error)
        }
        AudioServicePlugin.setFlutterEngineArguments(flutterRendererShellArgs())
        AudioServicePlugin.setFlutterEngineConfigurator(SharedEngineChannels::configure)
        AudioServicePlugin.setQueueArtResolver(CoverContentProvider.queueArtResolver(this))
    }
}
