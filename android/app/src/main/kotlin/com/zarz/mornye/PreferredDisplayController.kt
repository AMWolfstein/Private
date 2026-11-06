package com.zarz.mornye

import android.app.Activity
import android.hardware.display.DisplayManager
import android.os.Handler
import android.os.Looper
import android.view.Display
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

internal data class PreferredMode(val id: Int, val width: Int, val height: Int, val hz: Float)

/** A window preference only: neither a system setting nor a presentation guarantee. */
internal fun preferred60Mode(modes: List<PreferredMode>, current: PreferredMode): PreferredMode? =
    modes.filter { it.width == current.width && it.height == current.height && kotlin.math.abs(it.hz - 60f) <= 1f }
        .minByOrNull { kotlin.math.abs(it.hz - 60f) }

/** Bounded event history, independent of Flutter frame delivery. */
internal class DisplayModeHistory {
    private var lastMode: Pair<Int, Float>? = null
    var transitions = 0
        private set
    private val events = ArrayDeque<Map<String, Any>>()
    val changes: List<Map<String, Any>> get() = events.toList()

    fun observe(id: Int, hz: Float, atMs: Long) {
        val signature = id to hz
        if (lastMode != null && lastMode != signature) {
            transitions++
            if (events.size == 32) events.removeFirst()
            events.addLast(mapOf("at_ms" to atMs, "mode_id" to id, "hz" to hz.toDouble()))
        }
        lastMode = signature
    }
    fun reset() { transitions = 0; events.clear(); lastMode = null }
}

internal class PreferredDisplayController(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : DisplayManager.DisplayListener {
    private val manager = activity.getSystemService(DisplayManager::class.java)
    private val channel = MethodChannel(messenger, "com.zarz.mornye/performance_display")
    private val handler = Handler(Looper.getMainLooper())
    private var listening = false
    private val history = DisplayModeHistory()

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getState" -> result.success(state())
                "resetStatistics" -> { history.reset(); result.success(state()) }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun display(): Display = activity.windowManager.defaultDisplay
    private fun Display.Mode.model() = PreferredMode(modeId, physicalWidth, physicalHeight, refreshRate)

    fun start() {
        if (!listening) {
            manager.registerDisplayListener(this, handler)
            listening = true
        }
        applyPreference()
    }

    fun stop() {
        if (listening) manager.unregisterDisplayListener(this)
        listening = false
    }

    fun close() {
        stop()
        channel.setMethodCallHandler(null)
    }

    fun applyPreference() {
        val display = display()
        val target = preferred60Mode(display.supportedModes.map { it.model() }, display.mode.model())
        val attributes = activity.window.attributes
        val wanted = target?.id ?: 0
        if (attributes.preferredDisplayModeId != wanted || attributes.preferredRefreshRate != 0f) {
            attributes.preferredDisplayModeId = wanted
            attributes.preferredRefreshRate = 0f
            activity.window.attributes = attributes
        }
        channel.invokeMethod("onState", state())
    }

    private fun state(): Map<String, Any> {
        val display = display()
        val mode = display.mode
        history.observe(mode.modeId, mode.refreshRate, System.currentTimeMillis())
        val requestedId = activity.window.attributes.preferredDisplayModeId
        return mapOf(
            "requested_hz" to 60.0,
            "requested_mode_id" to requestedId,
            "request_supported" to (requestedId != 0),
            "active_mode_id" to mode.modeId,
            "active_hz" to mode.refreshRate.toDouble(),
            "display_hz" to display.refreshRate.toDouble(),
            "width" to mode.physicalWidth,
            "height" to mode.physicalHeight,
            "supported_hz" to display.supportedModes.filter {
                it.physicalWidth == mode.physicalWidth && it.physicalHeight == mode.physicalHeight
            }.map { it.refreshRate.toDouble() }.distinct().sorted(),
            "transition_count" to history.transitions,
            "changes" to history.changes,
        )
    }

    override fun onDisplayChanged(displayId: Int) {
        if (displayId == display().displayId) applyPreference()
    }
    override fun onDisplayAdded(displayId: Int) = Unit
    override fun onDisplayRemoved(displayId: Int) = Unit
}
