package com.amwolfstein.sistrum

import android.app.Application
import com.ryanheise.audioservice.AudioServicePlugin

class SistrumApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        AudioServicePlugin.setFlutterEngineArguments(flutterRendererShellArgs())
        AudioServicePlugin.setFlutterEngineConfigurator(SharedEngineChannels::configure)
        AudioServicePlugin.setQueueArtResolver(CoverContentProvider.queueArtResolver(this))
    }
}
