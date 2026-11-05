package com.amwolfstein.sistrum

import android.app.Activity
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.view.Display
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel

/**
 * Requests the user's preferred display refresh rate for the app's window and
 * reports what Android says the display is doing.
 *
 * The request is the window's `preferredDisplayModeId`: a mode at the current
 * resolution with the chosen rate, so the resolution never changes. Android
 * weighs it against its own policy (the system refresh-rate setting, battery
 * saver, thermal limits, the manufacturer's rules) and may keep another mode.
 * Nothing here changes a system setting, and a refused request is never
 * retried: the window keeps the same request until the preference changes.
 *
 * The request lives on the window, so Android ignores it while the app is not
 * visible. The display listener runs only while the Activity is started.
 *
 * State goes to Dart as an `onState` call on the same channel. The shared
 * engine can run Dart before an Activity adds this plugin; the push after
 * attach shows Dart a preference of 0 here, and Dart then sends the saved one.
 */
class DisplayRefreshRatePlugin : FlutterPlugin, ActivityAware {
    private var appContext: Context? = null
    private var methods: MethodChannel? = null

    private var activity: Activity? = null
    private var lifecycle: Lifecycle? = null
    private var listening = false
    private val handler = Handler(Looper.getMainLooper())

    /** Whole-number Hz; 0 means System Default. Survives Activity recreation. */
    private var preferenceHz = 0

    /** When the window request last changed (elapsed realtime), or 0. */
    private var requestChangedAt = 0L
    private var requestCount = 0
    private var modeChangeCount = 0
    private var lastActive: Pair<Int, Float>? = null
    private var lastEmitted: Map<String, Any>? = null

    private val settleCheck = Runnable { emit() }

    private val lifecycleObserver = LifecycleEventObserver { _, event ->
        when (event) {
            Lifecycle.Event.ON_START -> {
                startListening()
                apply()
                emit()
            }
            Lifecycle.Event.ON_STOP -> stopListening()
            else -> {}
        }
    }

    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) {}
        override fun onDisplayRemoved(displayId: Int) {}
        override fun onDisplayChanged(displayId: Int) {
            if (displayId != display()?.displayId) return
            // A resolution change moves the matching mode; the same rate at
            // the same resolution leaves the request untouched.
            apply()
            emit()
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getState" -> result.success(state())
                    "setPreference" -> {
                        val hz = (call.argument<Number>("hz") ?: 0).toInt()
                        preferenceHz = if (hz > 0) hz else 0
                        apply()
                        val state = state()
                        result.success(state)
                        emit(state)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detachActivity()
        methods?.setMethodCallHandler(null)
        methods = null
        appContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) = attachActivity(binding)

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        attachActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()

    override fun onDetachedFromActivity() = detachActivity()

    private fun attachActivity(binding: ActivityPluginBinding) {
        detachActivity()
        activity = binding.activity
        modeChangeCount = 0
        lastActive = null
        lastEmitted = null
        // A new Activity has a fresh window without the request; apply() sets it.
        requestChangedAt = 0L
        lifecycle = (binding.activity as? LifecycleOwner)?.lifecycle?.also {
            it.addObserver(lifecycleObserver)
        }
        apply()
        if (lifecycle == null) startListening()
        emit()
    }

    private fun detachActivity() {
        lifecycle?.removeObserver(lifecycleObserver)
        lifecycle = null
        stopListening()
        handler.removeCallbacks(settleCheck)
        activity = null
    }

    private fun startListening() {
        if (listening) return
        val manager = appContext?.getSystemService(DisplayManager::class.java) ?: return
        manager.registerDisplayListener(displayListener, handler)
        listening = true
    }

    private fun stopListening() {
        if (!listening) return
        appContext?.getSystemService(DisplayManager::class.java)
            ?.unregisterDisplayListener(displayListener)
        listening = false
    }

    @Suppress("DEPRECATION")
    private fun display(): Display? {
        val activity = activity ?: return null
        return if (Build.VERSION.SDK_INT >= 30) activity.display else activity.windowManager.defaultDisplay
    }

    private fun modes(display: Display): List<DisplayRefreshRatePolicy.Mode> =
        display.supportedModes.map { it.toPolicyMode() }

    private fun Display.Mode.toPolicyMode() =
        DisplayRefreshRatePolicy.Mode(modeId, physicalWidth, physicalHeight, refreshRate)

    /**
     * Brings the window request in line with the preference. Writes the
     * window attributes only when they differ, so repeated calls cost nothing.
     */
    private fun apply() {
        val window = activity?.window ?: return
        val display = display() ?: return
        val target = runCatching {
            DisplayRefreshRatePolicy.modeFor(modes(display), display.mode.toPolicyMode(), preferenceHz)
        }.getOrNull()
        val attributes = window.attributes
        val wantedId = target?.id ?: 0
        // Only the mode id is used. preferredRefreshRate stays 0: Android
        // ignores it when a mode id is set, and two requests could disagree.
        if (attributes.preferredDisplayModeId == wantedId && attributes.preferredRefreshRate == 0f) return
        attributes.preferredDisplayModeId = wantedId
        attributes.preferredRefreshRate = 0f
        window.attributes = attributes
        requestCount++
        requestChangedAt = SystemClock.elapsedRealtime()
        handler.removeCallbacks(settleCheck)
        handler.postDelayed(settleCheck, SETTLE_MS + 50)
    }

    private fun state(): Map<String, Any> {
        val display = display()
        val requestedId = activity?.window?.attributes?.preferredDisplayModeId ?: 0
        val base = mutableMapOf<String, Any>(
            "attached" to (display != null),
            "preferenceHz" to preferenceHz,
            "requestedModeId" to requestedId,
            "settled" to (requestChangedAt == 0L ||
                SystemClock.elapsedRealtime() - requestChangedAt >= SETTLE_MS),
            "powerSaveMode" to (appContext?.getSystemService(PowerManager::class.java)
                ?.isPowerSaveMode == true),
            "requestCount" to requestCount,
            "modeChangeCount" to modeChangeCount,
        )
        if (display == null) return base
        runCatching {
            val modes = modes(display)
            val current = display.mode.toPolicyMode()
            val active = current.id to current.refreshHz
            if (lastActive != null && lastActive != active) modeChangeCount++
            lastActive = active
            base["modeChangeCount"] = modeChangeCount
            base["supportedRates"] = DisplayRefreshRatePolicy.supportedRates(modes, current)
            base["requestedHz"] = modes.firstOrNull { it.id == requestedId }?.refreshHz?.toDouble() ?: 0.0
            base["activeModeId"] = current.id
            base["activeModeHz"] = current.refreshHz.toDouble()
            base["displayRefreshHz"] = display.refreshRate.toDouble()
            base["activeWidth"] = current.width
            base["activeHeight"] = current.height
            base["modes"] = modes.map { "${it.id}:${it.width}x${it.height}@${"%.2f".format(it.refreshHz)}" }
        }
        return base
    }

    /** Sends the state to Dart when it differs from the last one sent. */
    private fun emit(state: Map<String, Any> = state()) {
        val channel = methods ?: return
        if (state == lastEmitted) return
        lastEmitted = state
        channel.invokeMethod("onState", state)
    }

    private companion object {
        const val METHOD_CHANNEL = "com.amwolfstein.sistrum/display_refresh"

        /** How long a new request may take before a different active mode counts as not applied. */
        const val SETTLE_MS = 1500L
    }
}
