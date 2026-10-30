package com.amwolfstein.sistrum

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.android.FlutterFragment
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterShellArgs
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServicePlugin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.util.LinkedHashMap
import java.util.UUID
import java.util.concurrent.TimeUnit

class MainActivity: FlutterFragmentActivity() {
    // Mirrors audio_service's AudioServiceFragmentActivity: the shared engine
    // is owned by AudioServicePlugin's FlutterEngineCache. Without the
    // cached-engine-id + shouldDestroyEngineWithHost overrides, the activity
    // (via createFlutterFragment's destroyEngineWithFragment) destroys the
    // provided engine on exit while it stays registered in the cache; when
    // AudioService later stops, disposeFlutterEngine() destroys it a second
    // time and crashes with "FlutterJNI is not attached to native".
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        return AudioServicePlugin.getFlutterEngine(context)
    }

    override fun getCachedEngineId(): String {
        AudioServicePlugin.getFlutterEngine(this)
        return AudioServicePlugin.getFlutterEngineId()
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    private val CHANNEL = "com.amwolfstein.sistrum/backend"

    private val LIBRARY_SCAN_PROGRESS_STREAM_CHANNEL =
        "com.amwolfstein.sistrum/library_scan_progress_stream"
    private val LARGE_JSON_RESULT_FILE_KEY = "__json_file"
    private val LARGE_JSON_RESULT_FILE_THRESHOLD_BYTES = 256 * 1024
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var backendChannel: MethodChannel? = null
    private var audioOutputChannel: MethodChannel? = null
    internal val coreBackend: CoreBackend by lazy { createCoreBackend(applicationContext) }
    private val nativeBackendMethods = setOf(
        "setScreenAwake",
        "getBackendImplementations",
        "ensureInstallMarker",
        "getAppLogcat",

        "readFileMetadata",
        "editFileMetadata",

        "setLibraryCoverCacheDir",
        "scanLibraryFolderToNDJSONFile",
        "scanSafTreeToNDJSONFile",
        "getLibraryScanProgress",
        "getLibraryScanExitInfo",
        "cancelLibraryScan",
        "pauseLibraryScan",
        "resumeLibraryScan",
        "parseCueSheet",
        "pickSafTree",
        "safReleaseTree",

        "safExists",
        "safExistsBatch",
        "probeSafTreeReadAccess",
        "safDelete",
        "safStat",
        "safCopyToTemp",
        "safOpenPlaybackLease",
        "safClosePlaybackLease",
        "shareContentUri",
        "getSafFileModTimes",
        "safCreateFromPath",
        "writeTempToSaf",

        "extractCoverToFile",
        "releaseMemory",
        "releaseMemoryUnderPressure",

        "startBackgroundWork",
        "updateBackgroundWork",
        "stopBackgroundWork",

        "exitApp",
    )
    /**
     * Raw `logcat -d` output for this process only. Needs no READ_LOGS permission because
     * logcat restricts non-privileged readers to their own pid. Returns "" on any failure.
     */
    private fun readAppLogcat(): String {
        return try {
            val pid = android.os.Process.myPid()
            val process = ProcessBuilder("logcat", "-d", "-v", "threadtime", "--pid=$pid")
                .redirectErrorStream(true)
                .start()
            val output = process.inputStream.bufferedReader().use { it.readText() }
            if (!process.waitFor(APP_LOGCAT_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                process.destroyForcibly()
                android.util.Log.w("Sistrum", "App logcat read timed out")
                ""
            } else if (process.exitValue() != 0) {
                android.util.Log.w("Sistrum", "App logcat exited with ${process.exitValue()}")
                ""
            } else {
                output
            }
        } catch (error: Exception) {
            android.util.Log.w("Sistrum", "App logcat read failed", error)
            ""
        }
    }

    private val APP_LOGCAT_TIMEOUT_SECONDS = 5L
    private var libraryStorageReceiver: BroadcastReceiver? = null


    private var libraryScanProgressChannel: EventChannel? = null
    private var flutterBackCallback: OnBackPressedCallback? = null
    private val playbackLeaseLock = Any()
    private val playbackLeases = LinkedHashMap<String, ParcelFileDescriptor>()
    private val safTreeLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val result = pendingSafTreeResult
        pendingSafTreeResult = null

        fun deliver(payload: String?) {
            result?.success(payload)
        }

        if (activityResult.resultCode != Activity.RESULT_OK) {
            deliver(null)
            return@registerForActivityResult
        }

        val data = activityResult.data
        val uri = data?.data
        if (uri == null) {
            deliver(null)
            return@registerForActivityResult
        }

        val takeFlags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        var persistError: Exception? = null
        var persisted = false
        for (flags in safTreePersistFlags(
            takeFlags,
            Intent.FLAG_GRANT_READ_URI_PERMISSION,
            Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
        )) {
            try {
                contentResolver.takePersistableUriPermission(uri, flags)
                persisted = true
                break
            } catch (e: Exception) {
                persistError = e
            }
        }
        if (!persisted) {
            // A tree whose grant is not persisted loses access after restart;
            // never hand it to Dart as a usable library source. Log only the
            // error class: provider messages can embed the user's folder URI.
            android.util.Log.w(
                "Sistrum",
                "Failed to persist SAF permission: ${persistError?.javaClass?.simpleName ?: "no-grant"}",
            )
            deliver(errorJson("Could not keep access to the selected folder; pick it again"))
            return@registerForActivityResult
        }

        val payload = JSONObject()
        payload.put("tree_uri", uri.toString())
        payload.put("display_name", resolveSafDisplayPath(uri))
        val storageId = resolveSafStorageId(uri)
        val volume = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            getSystemService(StorageManager::class.java).storageVolumes.firstOrNull {
                (storageId == "primary" && it.isPrimary) ||
                    (!it.uuid.isNullOrBlank() && it.uuid.equals(storageId, ignoreCase = true))
            }
        } else {
            null
        }
        payload.put("volume_id", storageId ?: JSONObject.NULL)
        payload.put(
            "is_removable",
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                volume?.isRemovable ?: (storageId != null && storageId != "primary")
            } else {
                storageId != null && storageId != "primary"
            },
        )
        deliver(payload.toString())
    }

    private fun resolveSafStorageId(treeUri: Uri): String? {
        return try {
            DocumentsContract.getTreeDocumentId(treeUri)
                ?.substringBefore(':')
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Resolve a SAF tree URI to a human-readable path.
     * e.g. "content://...tree/primary%3AMusic" -> "/storage/emulated/0/Music"
     *      "content://...tree/1234-5678%3AMusic" -> "SD Card/Music"
     */
    private fun resolveSafDisplayPath(treeUri: Uri): String {
        try {
            val docId = android.provider.DocumentsContract.getTreeDocumentId(treeUri)
            if (docId.isNullOrEmpty()) return treeUri.toString()

            val parts = docId.split(":", limit = 2)
            val storageId = parts.getOrNull(0) ?: return docId
            val subPath = parts.getOrNull(1) ?: ""

            val prefix = if (storageId == "primary") {
                "/storage/emulated/0"
            } else {
                val volumeName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    getSystemService(StorageManager::class.java).storageVolumes
                        .firstOrNull { it.uuid.equals(storageId, ignoreCase = true) }
                        ?.getDescription(this)
                } else {
                    null
                }
                volumeName?.takeIf { it.isNotBlank() } ?: "External storage"
            }

            return if (subPath.isEmpty()) prefix else "$prefix/$subPath"
        } catch (e: Exception) {
            android.util.Log.w("Sistrum", "Failed to resolve SAF display path: ${e.message}")
            return treeUri.toString()
        }
    }

    data class SafScanProgress(
        var totalFiles: Int = 0,
        var scannedFiles: Int = 0,
        var currentFile: String = "",
        var errorCount: Int = 0,
        var progressPct: Double = 0.0,
        var isComplete: Boolean = false,
        /** Failed documents and why, up to [REPORTED_SCAN_FAILURES]. The list
         * is replaced, never changed, so a snapshot can be read unlocked. */
        var failures: List<Pair<String, String>> = emptyList(),
    )

    companion object {

        // audio_service keeps the engine across Activity recreation. Retain
        // its outstanding picker reply for the same lifetime, not the Activity.
        private var pendingSafTreeResult: MethodChannel.Result? = null

        // The Flutter engine outlives a recreated Activity. SAF scan state and
        // its progress stream must survive with it, or a recreated Activity
        // reports an idle backend while the scan is still running.
        internal val safScanLock = Any()
        // Held for a whole SAF scan: a cancelled scan can still be appending to
        // its NDJSON output, and a new scan must wait for it to finish.
        internal val safScanRunLock = Any()
        internal var safScanProgress = SafScanProgress()
        @Volatile internal var safScanCancel = false
        @Volatile internal var safScanPaused = false
        @Volatile internal var safScanActive = false
    }

    class ImpellerAwareFlutterFragment : FlutterFragment() {
        override fun getFlutterShellArgs(): FlutterShellArgs {
            val args = super.getFlutterShellArgs()
            for (argument in flutterRendererShellArgs()) args.add(argument)
            return args
        }
    }

    override fun createFlutterFragment(): FlutterFragment {
        val backgroundMode = getBackgroundMode()
        val renderMode = getRenderMode()
        val transparencyMode =
            if (backgroundMode == BackgroundMode.opaque) TransparencyMode.opaque else TransparencyMode.transparent
        val shouldDelayFirstAndroidViewDraw = renderMode == RenderMode.surface

        getCachedEngineId()?.let { cachedEngineId ->
            return FlutterFragment.CachedEngineFragmentBuilder(
                ImpellerAwareFlutterFragment::class.java,
                cachedEngineId
            )
                .renderMode(renderMode)
                .transparencyMode(transparencyMode)
                .handleDeeplinking(shouldHandleDeeplinking())
                .shouldAttachEngineToActivity(shouldAttachEngineToActivity())
                .destroyEngineWithFragment(shouldDestroyEngineWithHost())
                .shouldDelayFirstAndroidViewDraw(shouldDelayFirstAndroidViewDraw)
                .shouldAutomaticallyHandleOnBackPressed(true)
                .build()
        }

        getCachedEngineGroupId()?.let { cachedEngineGroupId ->
            return FlutterFragment.NewEngineInGroupFragmentBuilder(
                ImpellerAwareFlutterFragment::class.java,
                cachedEngineGroupId
            )
                .dartEntrypoint(getDartEntrypointFunctionName())
                .initialRoute(getInitialRoute())
                .handleDeeplinking(shouldHandleDeeplinking())
                .renderMode(renderMode)
                .transparencyMode(transparencyMode)
                .shouldAttachEngineToActivity(shouldAttachEngineToActivity())
                .shouldDelayFirstAndroidViewDraw(shouldDelayFirstAndroidViewDraw)
                .shouldAutomaticallyHandleOnBackPressed(true)
                .build()
        }

        return FlutterFragment.NewEngineFragmentBuilder(ImpellerAwareFlutterFragment::class.java)
            .dartEntrypoint(getDartEntrypointFunctionName())
            .dartLibraryUri(getDartEntrypointLibraryUri() ?: "")
            .dartEntrypointArgs(getDartEntrypointArgs() ?: emptyList())
            .initialRoute(getInitialRoute())
            .appBundlePath(getAppBundlePath())
            .flutterShellArgs(FlutterShellArgs.fromIntent(intent))
            .handleDeeplinking(shouldHandleDeeplinking())
            .renderMode(renderMode)
            .transparencyMode(transparencyMode)
            .shouldAttachEngineToActivity(shouldAttachEngineToActivity())
            .shouldDelayFirstAndroidViewDraw(shouldDelayFirstAndroidViewDraw)
            .shouldAutomaticallyHandleOnBackPressed(true)
            .build()
    }

    internal fun bridgeJsonResult(payload: String): Any {
        // Decide on char count where possible: UTF-8 size is >= length and
        // <= 3*length, so only the ambiguous band needs the full encode —
        // avoids duplicating multi-MB payloads just to measure them.
        val definitelySmall = payload.length * 3 < LARGE_JSON_RESULT_FILE_THRESHOLD_BYTES
        val definitelyLarge = payload.length >= LARGE_JSON_RESULT_FILE_THRESHOLD_BYTES
        if (definitelySmall ||
            (!definitelyLarge &&
                payload.toByteArray(Charsets.UTF_8).size < LARGE_JSON_RESULT_FILE_THRESHOLD_BYTES)
        ) {
            return payload
        }

        return try {
            val file = File(cacheDir, "bridge_json_${System.nanoTime()}.json")
            file.writeText(payload, Charsets.UTF_8)
            mapOf(LARGE_JSON_RESULT_FILE_KEY to file.absolutePath)
        } catch (e: Exception) {
            android.util.Log.w(
                "Sistrum",
                "Failed to spill large bridge JSON result to file: ${e.message}",
            )
            payload
        }
    }

    /**
     * Streams a JSON payload piecewise to a cache spill file so large scan
     * results never materialize on the Java heap. [result] hands back the
     * payload inline when it is small (same contract as [bridgeJsonResult]),
     * otherwise the spill-file map.
     */
    internal inner class SpillJsonWriter {
        val file = File(cacheDir, "bridge_json_${System.nanoTime()}.json")
        private val writer = file.bufferedWriter(Charsets.UTF_8)

        fun raw(fragment: String) = writer.write(fragment)

        fun result(): Any {
            writer.close()
            if (file.length() < LARGE_JSON_RESULT_FILE_THRESHOLD_BYTES) {
                val payload = file.readText(Charsets.UTF_8)
                file.delete()
                return payload
            }
            return mapOf(LARGE_JSON_RESULT_FILE_KEY to file.absolutePath)
        }

        fun abandon() {
            try { writer.close() } catch (_: Exception) {}
            try { file.delete() } catch (_: Exception) {}
        }
    }

    private fun startLibraryScanProgressStream(sink: EventChannel.EventSink) {
        val backend = coreBackend
        SafScanProgressStream.start(sink) { readLibraryScanProgressJson(backend) }
    }

    private fun stopLibraryScanProgressStream() {
        SafScanProgressStream.stop()
    }

    // Disable Flutter's built-in deep linking so incoming ACTION_VIEW URLs are
    // not forwarded to GoRouter; the app only opens local files.
    override fun shouldHandleDeeplinking(): Boolean = false

    // Bridge spill files and SAF temp copies are deleted after use on the
    // normal path, but a process kill mid-operation orphans them in cacheDir
    // forever (names embed nanoTime, so nothing overwrites them). Sweep
    // leftovers from previous sessions; the 1h age guard protects in-flight
    // files from concurrent work in this session.
    private fun sweepStaleCacheFiles() {
        scope.launch(Dispatchers.IO) {
            try {
                val cutoff = System.currentTimeMillis() - 60 * 60 * 1000L
                cacheDir.listFiles()?.forEach { file ->
                    val stale = file.isFile &&
                        file.lastModified() < cutoff &&
                        (file.name.startsWith("bridge_json_") ||
                            file.name.startsWith("saf_") ||
                            file.name.startsWith("native_saf_") ||
                            file.name.startsWith("ms_"))
                    if (stale) file.delete()
                }
            } catch (_: Exception) {}
        }
    }

    /**
     * Creates an install-scoped marker in noBackupFilesDir. A platform restore
     * can bring SharedPreferences back after reinstall, but this marker is never
     * backed up. Package timestamps distinguish that case from the first app
     * update after this marker was introduced, so existing users are not sent
     * through onboarding again.
     */
    private fun ensureInstallMarker(): Map<String, Any> {
        val marker = File(noBackupFilesDir, "installation_state_v1")
        val markerExisted = marker.isFile
        val packageInfo = @Suppress("DEPRECATION")
        packageManager.getPackageInfo(packageName, 0)
        val installTimestampDelta = kotlin.math.abs(
            packageInfo.lastUpdateTime - packageInfo.firstInstallTime
        )
        val looksLikeFreshPackageInstall = installTimestampDelta <= 10_000L

        var markerCreated = markerExisted
        if (!markerExisted) {
            markerCreated = try {
                marker.parentFile?.mkdirs()
                marker.writeText(
                    "created_at=${System.currentTimeMillis()}\n" +
                        "version_code=${BuildConfig.VERSION_CODE}\n"
                )
                true
            } catch (e: Exception) {
                android.util.Log.w(
                    "Sistrum",
                    "Failed to create installation marker: ${e.message}"
                )
                false
            }
        }

        return mapOf(
            "marker_existed" to markerExisted,
            "marker_created" to markerCreated,
            "fresh_package_install" to looksLikeFreshPackageInstall,
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Ensure the shared audio_service engine exists before the activity
        // delegate looks it up by cached id (see getCachedEngineId above).
        AudioServicePlugin.getFlutterEngine(this)
        super.onCreate(savedInstanceState)

        PlayerWidgetBridge.handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        PlayerWidgetBridge.handleIntent(intent)
    }

    internal fun reportLibraryScanError(path: String, operation: String, message: String) {
        android.util.Log.e("Sistrum", "Library scan: $operation [$path]: $message")
        recordSafScanFailure(path, message)
        val payload = mapOf(
            "path" to path,
            "operation" to operation,
            "message" to message,
        )
        runOnUiThread {
            backendChannel?.invokeMethod("libraryScanError", payload)
        }
    }

    /**
     * Opens a short-lived descriptor lease for zero-copy SAF playback. The
     * returned proc path identifies the lease. The Android audio plugin must
     * duplicate this descriptor, never reopen it (AppFuse rejects reopening).
     * A small hard cap protects against abandoned method calls.
     */
    private fun openSafPlaybackLease(uriStr: String): Map<String, String>? {
        if (!uriStr.startsWith("content://")) return null
        val descriptor = try {
            contentResolver.openFileDescriptor(Uri.parse(uriStr), "r")
        } catch (e: Exception) {
            android.util.Log.w("Sistrum", "Failed to open SAF playback descriptor: ${e.message}")
            null
        } ?: return null

        if (!isSeekableSafDescriptor(descriptor)) {
            descriptor.close()
            return null
        }
        val token = UUID.randomUUID().toString()
        synchronized(playbackLeaseLock) {
            while (playbackLeases.size >= 4) {
                val oldest = playbackLeases.entries.firstOrNull() ?: break
                playbackLeases.remove(oldest.key)
                try {
                    oldest.value.close()
                } catch (_: Exception) {}
            }
            playbackLeases[token] = descriptor
        }
        return mapOf(
            "token" to token,
            "path" to "/proc/self/fd/${descriptor.fd}",
            "display_name" to buildUriDisplayName(Uri.parse(uriStr)),
        )
    }

    private fun closeSafPlaybackLease(token: String) {
        if (token.isBlank()) return
        val descriptor = synchronized(playbackLeaseLock) {
            playbackLeases.remove(token)
        } ?: return
        try {
            descriptor.close()
        } catch (_: Exception) {}
    }

    private fun closeAllSafPlaybackLeases() {
        val descriptors = synchronized(playbackLeaseLock) {
            val openDescriptors = playbackLeases.values.toList()
            playbackLeases.clear()
            openDescriptors
        }
        descriptors.forEach { descriptor ->
            try {
                descriptor.close()
            } catch (_: Exception) {}
        }
    }

    override fun onDestroy() {
        if (isFinishing) {
            val pending = pendingSafTreeResult
            pendingSafTreeResult = null
            pending?.success(null)
        }
        audioOutputChannel?.setMethodCallHandler(null)
        audioOutputChannel = null
        // The engine outlives this Activity. Clear its handlers so it does not
        // keep the destroyed Activity reachable; the next Activity installs
        // fresh ones in configureFlutterEngine.
        backendChannel?.setMethodCallHandler(null)
        backendChannel = null
        libraryScanProgressChannel?.setStreamHandler(null)
        libraryScanProgressChannel = null
        libraryStorageReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {}
        }
        libraryStorageReceiver = null
        // The backend belongs to the process/shared Flutter engine. Activity
        // recreation must not shut it down or wait for active scans on the UI thread.
        if (isFinishing) {
            stopLibraryScanProgressStream()
            scope.cancel()
        }
        closeAllSafPlaybackLeases()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PlayerWidgetBridge.attach(this, flutterEngine)
        // Select and initialize the runtime before Flutter can dispatch a call.
        val selectedBackend = coreBackend
        sweepStaleCacheFiles()

        // Always-enabled back callback to ensure back presses reach Flutter.
        // Nested tab navigators can incorrectly set frameworkHandlesBack(false),
        // which disables Flutter's own OnBackPressedCallback and causes the
        // system default (finish activity) to run. This callback guarantees
        // popRoute is always forwarded to Flutter, where PopScope handles it.
        flutterBackCallback = object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                flutterEngine.navigationChannel.popRoute()
            }
        }
        onBackPressedDispatcher.addCallback(this, flutterBackCallback!!)

        val messenger = flutterEngine.dartExecutor.binaryMessenger
        if (!flutterEngine.plugins.has(UsbBitPerfectPlugin::class.java)) {
            flutterEngine.plugins.add(UsbBitPerfectPlugin())
        }
        if (!flutterEngine.plugins.has(MusicHapticsPlugin::class.java)) {
            flutterEngine.plugins.add(MusicHapticsPlugin())
        }
        audioOutputChannel = MethodChannel(messenger, "com.amwolfstein.sistrum/audio_output").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method != "show") {
                    result.notImplemented()
                } else {
                    try {
                        val shown = if (Build.VERSION.SDK_INT >= 34) {
                            android.media.MediaRouter2.getInstance(this).showSystemOutputSwitcher()
                        } else {
                            // Older Android releases do not expose a public output picker.
                            startActivity(Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS))
                            true
                        }
                        result.success(shown)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
            }
        }

        libraryScanProgressChannel = EventChannel(
            messenger,
            LIBRARY_SCAN_PROGRESS_STREAM_CHANNEL,
        ).also { channel ->
            channel.setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        if (events != null) {
                            startLibraryScanProgressStream(events)
                        }
                    }

                    override fun onCancel(arguments: Any?) {
                        stopLibraryScanProgressStream()
                    }
                },
            )
        }

        val channel = MethodChannel(messenger, CHANNEL)
        backendChannel = channel
        registerLibraryStorageReceiver()

        channel.setMethodCallHandler { call, result ->
            scope.launch {
                try {
                    if (call.method !in nativeBackendMethods && dispatchBackendApplication(call, result)) {
                        return@launch
                    }
                    when (call.method) {

                        "setScreenAwake" -> {
                            val flag = android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                            if (call.argument<Boolean>("enabled") == true) {
                                window.addFlags(flag)
                            } else {
                                window.clearFlags(flag)
                            }
                            result.success(null)
                        }

                        "getAppLogcat" -> {
                            // Read off the main thread; failures return "" and are logged natively.
                            val text = withContext(Dispatchers.IO) { readAppLogcat() }
                            result.success(text)
                        }

                        "ensureInstallMarker" -> {
                            val installState = withContext(Dispatchers.IO) {
                                ensureInstallMarker()
                            }
                            result.success(installState)
                        }

                        "exitApp" -> {
                            flutterBackCallback?.isEnabled = false
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                                finishAndRemoveTask()
                            } else {
                                finish()
                            }
                            result.success(null)
                        }

                        "getBackendImplementations" -> {
                            result.success(
                                mapOf(
                                    "filename" to coreBackend.implementation,
                                    "file_metadata" to coreBackend.fileMetadataImplementation(call.argument<String>("file_path") ?: ""),
                                    "library" to coreBackend.implementation,
                                )
                            )
                        }


                        "pickSafTree" -> {
                            if (pendingSafTreeResult != null) {
                                result.error("saf_pending", "SAF picker already active", null)
                                return@launch
                            }
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                            intent.addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                            )
                            val resolver = intent.resolveActivity(packageManager)
                            if (resolver == null) {
                                result.error("saf_unavailable", "No folder picker available on this device", null)
                                return@launch
                            }
                            pendingSafTreeResult = result
                            try {
                                android.util.Log.i("Sistrum", "Launching SAF picker via $resolver")
                                safTreeLauncher.launch(intent)
                            } catch (e: Exception) {
                                pendingSafTreeResult = null
                                android.util.Log.e("Sistrum", "Failed to launch SAF picker: ${e.message}", e)
                                result.error(
                                    "saf_launch_failed",
                                    e.message ?: "Failed to launch folder picker",
                                    null
                                )
                            }
                        }


                        "safExists" -> {
                            val uriStr = call.argument<String>("uri") ?: ""
                            val exists = withContext(Dispatchers.IO) {
                                val uri = Uri.parse(uriStr)
                                DocumentFile.fromSingleUri(this@MainActivity, uri)?.exists() == true
                            }
                            result.success(exists)
                        }
                        "safReleaseTree" -> {
                            val uriStr = call.argument<String>("tree_uri") ?: ""
                            withContext(Dispatchers.IO) {
                                releaseSafTreeGrant(uriStr)
                            }
                            result.success(null)
                        }
                        "safExistsBatch" -> {
                            val urisJson = call.argument<String>("uris_json") ?: "[]"
                            val response = withContext(Dispatchers.IO) {
                                safExistsBatch(urisJson)
                            }
                            result.success(response)
                        }
                        "probeSafTreeReadAccess" -> {
                            val uriStr = call.argument<String>("tree_uri") ?: ""
                            val readable = withContext(Dispatchers.IO) {
                                probeSafTreeReadAccess(
                                    hasReadPermission = {
                                        val uri = Uri.parse(uriStr)
                                        val root = DocumentsContract.buildDocumentUriUsingTree(
                                            uri,
                                            DocumentsContract.getTreeDocumentId(uri),
                                        )
                                        checkUriPermission(
                                            root,
                                            android.os.Process.myPid(),
                                            android.os.Process.myUid(),
                                            Intent.FLAG_GRANT_READ_URI_PERMISSION,
                                        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
                                    },
                                    readRoot = {
                                        val uri = Uri.parse(uriStr)
                                        val root = DocumentsContract.buildDocumentUriUsingTree(
                                            uri,
                                            DocumentsContract.getTreeDocumentId(uri),
                                        )
                                        val rootPresent = contentResolver.query(
                                            root,
                                            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID),
                                            null, null, null,
                                        )?.use { cursor ->
                                            when {
                                                cursor.moveToFirst() -> true
                                                cursor.extras.getBoolean(DocumentsContract.EXTRA_LOADING, false) -> null
                                                else -> false
                                            }
                                        }
                                        if (rootPresent == true) {
                                            true
                                        } else {
                                            // A reconnecting remote provider may not have
                                            // queryDocument metadata yet. A completed child
                                            // listing is stronger evidence of read access.
                                            val directory = DocumentFile.fromTreeUri(this@MainActivity, uri)
                                            if (directory != null && listSafChildrenOrThrow(directory).isNotEmpty()) {
                                                true
                                            } else {
                                                rootPresent
                                            }
                                        }
                                    },
                                    onFailure = { error ->
                                        android.util.Log.w("Sistrum", "SAF library read probe failed", error)
                                    },
                                )
                            }
                            result.success(readable)
                        }
                        "safDelete" -> {
                            val uriStr = call.argument<String>("uri") ?: ""
                            val deleted = withContext(Dispatchers.IO) {
                                val uri = Uri.parse(uriStr)
                                DocumentFile.fromSingleUri(this@MainActivity, uri)?.delete() == true
                            }
                            result.success(deleted)
                        }
                        "safStat" -> {
                            val uriStr = call.argument<String>("uri") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                querySafDocumentStat(contentResolver, Uri.parse(uriStr)).toString()
                            }
                            result.success(response)
                        }


                        "safCopyToTemp" -> {
                            val uriStr = call.argument<String>("uri") ?: ""
                            val tempPath = withContext(Dispatchers.IO) {
                                copyUriToTemp(Uri.parse(uriStr))
                            }
                            result.success(tempPath)
                        }
                        "safOpenPlaybackLease" -> {
                            val uriStr = call.argument<String>("uri") ?: ""
                            val lease = withContext(Dispatchers.IO) {
                                openSafPlaybackLease(uriStr)
                            }
                            result.success(lease)
                        }
                        "safClosePlaybackLease" -> {
                            val token = call.argument<String>("token") ?: ""
                            closeSafPlaybackLease(token)
                            result.success(null)
                        }
                        "safCreateFromPath" -> {
                            val treeUriStr = call.argument<String>("tree_uri") ?: ""
                            val relativeDir = call.argument<String>("relative_dir") ?: ""
                            val fileName = SafFileOps.sanitizeFilename(call.argument<String>("file_name") ?: "")
                            val mimeType = call.argument<String>("mime_type") ?: "application/octet-stream"
                            val srcPath = call.argument<String>("src_path") ?: ""
                            val createdUri = withContext(Dispatchers.IO) {
                                if (treeUriStr.isBlank()) return@withContext null
                                if (fileName.isBlank()) return@withContext null
                                val dir = SafFileOps.ensureDocumentDir(this@MainActivity, Uri.parse(treeUriStr), relativeDir) ?: return@withContext null
                                val existing = findSafChild(this@MainActivity, dir, fileName)
                                val createdNew = existing == null
                                val doc = SafFileOps.createOrReuseDocumentFile(this@MainActivity, dir, mimeType, fileName)
                                    ?: return@withContext null
                                if (!writeUriFromPath(doc.uri, srcPath)) {
                                    if (createdNew) {
                                        doc.delete()
                                    }
                                    return@withContext null
                                }
                                doc.uri.toString()
                            }
                            result.success(createdUri)
                        }



                        "shareContentUri" -> {
                            val uriStr = call.argument<String>("uri") ?: ""
                            val title = call.argument<String>("title") ?: ""
                            try {
                                val uri = Uri.parse(uriStr)
                                val type = contentResolver.getType(uri) ?: "audio/*"
                                val shareIntent = Intent(Intent.ACTION_SEND).apply {
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    setType(type)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    if (title.isNotBlank()) {
                                        putExtra(Intent.EXTRA_SUBJECT, title)
                                    }
                                }
                                startActivity(Intent.createChooser(shareIntent, title.ifBlank { "Share" }))
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("share_failed", e.message, null)
                            }
                        }


                        "readFileMetadata" -> {
                            val filePath = call.argument<String>("file_path") ?: ""
                            val displayName = call.argument<String>("display_name") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    if (filePath.startsWith("content://")) {
                                        readCompleteMetadataFromUri(Uri.parse(filePath), displayName)
                                            ?.toString() ?: errorJson("Failed to read SAF metadata")
                                    } else {
                                        coreBackend.readFileMetadata(filePath, displayName)
                                    }
                                } catch (e: Exception) {
                                    errorJson(e.message ?: "Failed to read metadata")
                                }
                            }
                            result.success(response)
                        }

                        "editFileMetadata" -> {
                            val filePath = call.argument<String>("file_path") ?: ""
                            val metadataJson = call.argument<String>("metadata_json") ?: "{}"
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    if (filePath.startsWith("content://")) {
                                        val uri = Uri.parse(filePath)
                                        val tempPath = copyUriToTemp(uri)
                                            ?: return@withContext """{"error":"Failed to copy SAF file to temp"}"""
                                        try {
                                            val raw = coreBackend.editFileMetadata(tempPath, metadataJson)
                                            val obj = JSONObject(raw)
                                            val method = obj.optString("method", "")
                                            if (method == "ffmpeg") {
                                                // MP3/Opus: Dart needs to FFmpeg the temp file, then call writeTempToSaf
                                                obj.put("temp_path", tempPath)
                                                obj.put("saf_uri", filePath)
                                                return@withContext obj.toString()
                                                // Note: temp file NOT deleted here - Dart will clean up after FFmpeg + writeTempToSaf
                                            }
                            // FLAC: the backend wrote to temp, copy back now
                            val write = writeUriFromPathRecoverable(uri, tempPath)
                            if (!write.success) {
                                try { File(tempPath).delete() } catch (_: Exception) {}
                                return@withContext errorJson(
                                    write.error ?: "Failed to write metadata back to SAF file"
                                )
                            }
                            try { File(tempPath).delete() } catch (_: Exception) {}
                            raw
                                        } catch (e: Exception) {
                                            try { File(tempPath).delete() } catch (_: Exception) {}
                                            throw e
                                        }
                                    } else {
                                        coreBackend.editFileMetadata(filePath, metadataJson)
                                    }
                                } catch (e: Exception) {
                                    android.util.Log.e("Sistrum", "editFileMetadata failed: ${e.message}", e)
                                    """{"error":${org.json.JSONObject.quote(e.message ?: "unknown")}}"""
                                }
                            }
                            result.success(response)
                        }


                        "writeTempToSaf" -> {
                            val tempPath = call.argument<String>("temp_path") ?: ""
                            val safUri = call.argument<String>("saf_uri") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    val outcome = writeUriFromPathRecoverable(
                                        Uri.parse(safUri),
                                        tempPath,
                                    )
                                    JSONObject()
                                        .put("success", outcome.success)
                                        .apply {
                                            if (!outcome.success) {
                                                put("error", outcome.error ?: "Failed to write back to SAF")
                                            }
                                            outcome.recoveryPath?.let { put("recovery_path", it) }
                                        }
                                        .toString()
                                } finally {
                                    try { File(tempPath).delete() } catch (_: Exception) {}
                                }
                            }
                            result.success(response)
                        }


                        "extractCoverToFile" -> {
                            val audioPath = call.argument<String>("audio_path") ?: ""
                            val outputPath = call.argument<String>("output_path") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    if (audioPath.startsWith("content://")) {
                                        extractCoverFromUri(Uri.parse(audioPath), outputPath)
                                        """{"success":true}"""
                                    } else {
                                        coreBackend.extractCoverToFile(audioPath, outputPath)
                                        """{"success":true}"""
                                    }
                                } catch (e: Exception) {
                                    errorJson(e.message ?: "Failed to extract cover")
                                }
                            }
                            result.success(response)
                        }

                        "startBackgroundWork" -> {
                            result.success(
                                BackgroundWorkService.start(
                                    this@MainActivity,
                                    call.argument<String>("kind") ?: "",
                                    call.argument<String>("title") ?: "",
                                    call.argument<String>("text") ?: "",
                                ),
                            )
                        }
                        "updateBackgroundWork" -> {
                            BackgroundWorkService.update(
                                call.argument<String>("kind") ?: "",
                                call.argument<String>("title") ?: "",
                                call.argument<String>("text") ?: "",
                                call.argument<Int>("progress") ?: -1,
                            )
                            result.success(null)
                        }
                        "stopBackgroundWork" -> {
                            BackgroundWorkService.stop(call.argument<String>("kind") ?: "")
                            result.success(null)
                        }

                        "releaseMemory" -> {
                            withContext(Dispatchers.IO) {
                                coreBackend.releaseIdleResources()
                            }
                            result.success(null)
                        }
                        "releaseMemoryUnderPressure" -> {
                            withContext(Dispatchers.IO) {
                                coreBackend.releaseMemoryUnderPressure()
                            }
                            android.util.Log.d("Sistrum", "Backend memory pressure release completed")
                            result.success(null)
                        }

                        "setLibraryCoverCacheDir" -> {
                            val cacheDir = call.argument<String>("cache_dir") ?: ""
                            withContext(Dispatchers.IO) {
                                coreBackend.setLibraryCoverCacheDirectory(cacheDir)
                            }
                            result.success(null)
                        }
                        "scanLibraryFolderToNDJSONFile" -> {
                            val folderPath = call.argument<String>("folder_path") ?: ""
                            val outputPath = call.argument<String>("output_path") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                safScanActive = false
                                val count = coreBackend.scanLibraryFolderToNdjsonFile(
                                    folderPath,
                                    outputPath,
                                )
                                mapOf(
                                    "path" to outputPath,
                                    "count" to count,
                                    "error_count" to JSONObject(coreBackend.getLibraryScanProgress())
                                        .getInt("error_count"),
                                )
                            }
                            result.success(response)
                        }
                        "scanSafTreeToNDJSONFile" -> {
                            val treeUri = call.argument<String>("tree_uri") ?: ""
                            val outputPath = call.argument<String>("output_path") ?: ""
                            val sourceHasRows = call.argument<Boolean>("has_indexed_rows") ?: false
                            val response = withContext(Dispatchers.IO) {
                                scanSafTree(treeUri, outputPath, sourceHasRows)
                            }
                            result.success(response)
                        }
                        "getSafFileModTimes" -> {
                            val uris = call.argument<String>("uris") ?: "[]"
                            val response = withContext(Dispatchers.IO) {
                                getSafFileModTimes(uris)
                            }
                            result.success(response)
                        }
                        "getLibraryScanProgress" -> {
                            val response = withContext(Dispatchers.IO) {
                                if (safScanActive) {
                                    safProgressToJson()
                                } else {
                                    coreBackend.getLibraryScanProgress()
                                }
                            }
                            result.success(parseJsonPayload(response))
                        }
                        "getLibraryScanExitInfo" -> {
                            val startedAfter = call.argument<Number>("started_after")?.toLong() ?: 0L
                            val response = withContext(Dispatchers.IO) {
                                LibraryScanExitInfo.read(applicationContext, startedAfter)
                            }
                            result.success(response)
                        }
                        "cancelLibraryScan" -> {
                            withContext(Dispatchers.IO) {
                                safScanCancel = true
                                safScanPaused = false
                                coreBackend.cancelLibraryScan()
                            }
                            result.success(null)
                        }
                        "pauseLibraryScan" -> {
                            withContext(Dispatchers.IO) {
                                safScanPaused = true
                                coreBackend.pauseLibraryScan()
                            }
                            result.success(null)
                        }
                        "resumeLibraryScan" -> {
                            withContext(Dispatchers.IO) {
                                safScanPaused = false
                                coreBackend.resumeLibraryScan()
                            }
                            result.success(null)
                        }
                        "parseCueSheet" -> {
                            val cuePath = call.argument<String>("cue_path") ?: ""
                            val audioDir = call.argument<String>("audio_dir") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    if (cuePath.startsWith("content://")) {
                                        val uri = Uri.parse(cuePath)
                                        val tempCuePath = copyUriToTemp(uri, ".cue")
                                            ?: return@withContext """{"error":"Failed to copy CUE file to temp"}"""
                                        try {
                                            val audioFileName = extractCueAudioFileName(tempCuePath)

                                            val parentDir = safParentDir(uri)
                                            val audioDoc = if (parentDir != null) {
                                                val cueName = try {
                                                    DocumentFile.fromSingleUri(this@MainActivity, uri)?.name ?: ""
                                                } catch (_: Exception) { "" }
                                                findSafCueAudioSibling(this@MainActivity, parentDir, cueName, audioFileName)
                                            } else {
                                                null
                                            }

                                            if (audioDoc == null || !audioDoc.isFile) {
                                                return@withContext JSONObject()
                                                    .put("error", "Audio file not found for CUE sheet")
                                                    .toString()
                                            }

                                            // Preview parses the CUE text only; the selected audio
                                            // stays in SAF instead of copying a whole album to cache.
                                            val resultJson = coreBackend.parseCueSheetWithResolvedAudio(
                                                tempCuePath,
                                                audioDoc.uri.toString(),
                                            )
                                            JSONObject(resultJson)
                                                .put("cue_path", cuePath)
                                                .toString()
                                        } finally {
                                            try { File(tempCuePath).delete() } catch (_: Exception) {}
                                        }
                                    } else {
                                        coreBackend.parseCueSheet(cuePath, audioDir)
                                    }
                                } catch (e: Exception) {
                                    """{"error":${org.json.JSONObject.quote(e.message ?: "unknown")}}"""
                                }
                            }
                            result.success(response)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error(
                        ForegroundServiceStartPolicy.errorCode(e),
                        e.message,
                        null,
                    )
                }
            }
        }
    }

    private fun registerLibraryStorageReceiver() {
        if (libraryStorageReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                backendChannel?.invokeMethod(
                    "libraryStorageChanged",
                    mapOf("action" to (intent?.action ?: "")),
                )
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_MEDIA_MOUNTED)
            addAction(Intent.ACTION_MEDIA_UNMOUNTED)
            addAction(Intent.ACTION_MEDIA_EJECT)
            addAction(Intent.ACTION_MEDIA_REMOVED)
            addAction(Intent.ACTION_MEDIA_BAD_REMOVAL)
            addDataScheme("file")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(receiver, filter)
        }
        libraryStorageReceiver = receiver
    }
}
