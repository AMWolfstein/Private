package com.amwolfstein.sistrum

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import org.json.JSONObject
import java.io.File

/** Registration happens before Dart, regardless of whether an Activity or a
 * media browser creates the engine. No handler retains an Activity. */
internal object SharedEngineChannels {
    fun configure(context: Context, engine: FlutterEngine) {
        if (!engine.plugins.has(UsbBitPerfectPlugin::class.java)) engine.plugins.add(UsbBitPerfectPlugin())
        if (!engine.plugins.has(MusicHapticsPlugin::class.java)) engine.plugins.add(MusicHapticsPlugin())
        if (!engine.plugins.has(SharedPlaybackPlugin::class.java)) engine.plugins.add(SharedPlaybackPlugin())
        PlayerWidgetBridge.attach(context.applicationContext, engine)
    }

    fun leaseOwner(engine: FlutterEngine): Any? =
        (engine.plugins.get(SharedPlaybackPlugin::class.java) as? SharedPlaybackPlugin)?.leaseOwner

    fun restoreBackend(engine: FlutterEngine) {
        (engine.plugins.get(SharedPlaybackPlugin::class.java) as? SharedPlaybackPlugin)?.installBackend()
    }
}

/** Owns headless calls and descriptor cleanup for exactly one engine lifetime. */
internal class SharedPlaybackPlugin : FlutterPlugin {
    val leaseOwner = Any()
    private lateinit var context: Context
    private lateinit var backend: MethodChannel
    private lateinit var covers: MethodChannel
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        PlaybackFileLeases.attachOwner(leaseOwner)
        backend = MethodChannel(binding.binaryMessenger, "com.amwolfstein.sistrum/backend")
        covers = MethodChannel(binding.binaryMessenger, "com.amwolfstein.sistrum/covers")
        covers.setMethodCallHandler { call, result ->
            if (call.method == "provider") result.success(CoverContentProvider.describe(context))
            else result.notImplemented()
        }
        installBackend()
    }

    fun installBackend() {
        backend.setMethodCallHandler { call, result ->
            // Acquire a data-job cancellation lease before queueing it on IO.
            val id = if (call.method == "runNativeDataJob") call.argument<String>("request_id") else null
            val lease = id?.let { NativeDataJobs.acquire(it) }
            if (call.method == "cancelNativeDataJob") {
                NativeDataJobs.cancel(call.argument<String>("request_id") ?: "")
                result.success(null)
                return@setMethodCallHandler
            }
            val operation = scope.launch {
                try {
                    val response: Any? = withContext(Dispatchers.IO) {
                        when (call.method) {
                            "getLatestAppCrash" -> AppCrashReporter.pendingReport(noticeOnly = false)
                            "recordAppRuntimeError" -> {
                                AppCrashReporter.recordRuntimeError(
                                    call.argument<String>("error") ?: "",
                                    call.argument<String>("stack") ?: "",
                                    call.argument<String>("logs") ?: ""
                                )
                                null
                            }
                            "isCharging" -> ChargingState.read(context)
                            "ensureInstallMarker" -> InstallationMarker.ensure(context)
                            "safOpenPlaybackLease" -> PlaybackFileLeases.open(context, call.argument<String>("uri") ?: "", leaseOwner)
                            "safClosePlaybackLease" -> { PlaybackFileLeases.close(call.argument<String>("token") ?: ""); null }
                            "safExists" -> DocumentFile.fromSingleUri(context, Uri.parse(call.argument<String>("uri") ?: ""))?.exists() == true
                            "safExistsBatch" -> context.safExistsBatch(call.argument<String>("uris_json") ?: "[]")
                            "getSafFileModTimes" -> context.getSafFileModTimes(call.argument<String>("uris_json") ?: "[]")
                            "safStat" -> querySafDocumentStat(context.contentResolver, Uri.parse(call.argument<String>("uri") ?: "")).toString()
                            "safCopyToTemp" -> {
                                val input = context.contentResolver.openInputStream(Uri.parse(call.argument<String>("uri") ?: "")) ?: error("Unreadable document")
                                input.use {
                                    val output = createCoreBackend(context).createTemporaryMediaFile(context, "headless_audio_", ".audio")
                                    try { output.outputStream().use { stream -> it.copyTo(stream) }; output.path }
                                    catch (error: Exception) { output.delete(); throw error }
                                }
                            }
                            "readFileMetadata" -> withSource(call.argument<String>("file_path") ?: "") { path, name ->
                                val backend = createCoreBackend(context)
                                backend.readFileMetadata(path, call.argument<String>("display_name") ?: name)
                            }
                            "extractCoverToFile" -> withSource(call.argument<String>("audio_path") ?: "") { path, name ->
                                createCoreBackend(context).extractCoverToFile(path, call.argument<String>("output_path") ?: "", name)
                                "{\"success\":true}"
                            }
                            "runNativeDataJob" -> {
                                createCoreBackend(context)
                                val request = JSONObject(call.argument<String>("request_json") ?: error("Missing job request"))
                                // Scan orchestration still belongs to the attached Activity.
                                require(!request.optString("operation").startsWith("library_scan")) { "Scanning requires the app" }
                                RustCoreBackend.runDataJob(request, call.argument<ByteArray>("bytes") ?: byteArrayOf(), checkNotNull(lease))
                            }
                            else -> throw UnsupportedOperationException("Activity required: ${call.method}")
                        }
                    }
                    result.success(response)
                } catch (error: CancellationException) { throw error }
                catch (error: UnsupportedOperationException) { result.notImplemented() }
                catch (error: Exception) { result.error(ForegroundServiceStartPolicy.errorCode(error), error.message, null) }
            }
            // Also runs if cancellation prevents the coroutine body from starting.
            operation.invokeOnCompletion { if (id != null && lease != null) NativeDataJobs.release(id, lease) }
        }
    }

    private fun <T> withSource(source: String, action: (String, String) -> T): T {
        if (!source.startsWith("content://")) return action(source, File(source).name)
        val lease = PlaybackFileLeases.open(context, source, leaseOwner) ?: error("Document is not seekable")
        try { return action(lease.getValue("path"), lease.getValue("display_name")) }
        finally { PlaybackFileLeases.close(lease.getValue("token")) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        backend.setMethodCallHandler(null)
        covers.setMethodCallHandler(null)
        PlaybackFileLeases.retireOwner(leaseOwner)
        scope.coroutineContext[Job]?.invokeOnCompletion { PlaybackFileLeases.closeOwner(leaseOwner) }
        scope.cancel()
    }
}
