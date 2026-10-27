package com.amwolfstein.sistrum

import android.util.Log
import io.flutter.plugin.common.EventChannel
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Pumps library-scan progress into the engine-level EventChannel sink.
 *
 * audio_service keeps the Flutter engine (and Dart's stream subscription)
 * alive across Activity re-creation. The pump therefore belongs to the
 * process, not to an Activity: it only captures the application-scoped
 * backend, and it keeps publishing while a new Activity recreates its channel
 * handler without Dart re-subscribing.
 */
internal object SafScanProgressStream {
    private const val POLL_MS = 400L
    private const val MAX_SINK_FAILURES = 3

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var job: Job? = null
    private var sink: EventChannel.EventSink? = null
    private var lastPayload: String? = null

    fun start(
        events: EventChannel.EventSink,
        readProgress: () -> String,
    ) {
        stop()
        sink = events
        lastPayload = null
        job = scope.launch {
            var sinkFailures = 0
            try {
                val initialPayload = withContext(Dispatchers.IO) { readProgress() }
                if (!isActive || sink !== events) return@launch
                lastPayload = initialPayload
                events.success(parseJsonPayload(initialPayload))
            } catch (error: Exception) {
                Log.w(
                    "SpotiFLAC",
                    "Library scan progress initial poll failed: ${error.message}",
                )
            }
            while (isActive && sink === events) {
                try {
                    val payload = withContext(Dispatchers.IO) { readProgress() }
                    if (!isActive || sink !== events) break
                    if (payload != lastPayload) {
                        lastPayload = payload
                        events.success(parseJsonPayload(payload))
                    }
                    sinkFailures = 0
                } catch (error: Exception) {
                    Log.w(
                        "SpotiFLAC",
                        "Library scan progress stream poll failed: ${error.message}",
                    )
                    sinkFailures++
                    if (sinkFailures >= MAX_SINK_FAILURES) break
                }
                delay(POLL_MS)
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
        sink = null
        lastPayload = null
    }
}

internal fun parseJsonPayload(payload: String): Any {
    return try {
        parseJsonValue(JSONTokener(payload).nextValue()) ?: payload
    } catch (_: Exception) {
        payload
    }
}

private fun parseJsonValue(value: Any?): Any? {
    return when (value) {
        null, JSONObject.NULL -> null
        is JSONObject -> {
            val map = LinkedHashMap<String, Any?>()
            val keys = value.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                map[key] = parseJsonValue(value.opt(key))
            }
            map
        }
        is JSONArray -> {
            val list = ArrayList<Any?>()
            for (i in 0 until value.length()) {
                list.add(parseJsonValue(value.opt(i)))
            }
            list
        }
        is Number, is Boolean, is String -> value
        else -> value.toString()
    }
}
