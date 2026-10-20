package com.zarz.spotiflac

import android.app.Application
import com.ryanheise.audioservice.AudioServicePlugin

class SpotiFlacApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        AudioServicePlugin.setFlutterEngineArguments(flutterRendererShellArgs())
    }
}
